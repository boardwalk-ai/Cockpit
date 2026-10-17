import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api/sse_client.dart' show SseException;
import '../../data/api/upload_api.dart' show BuildSnapshot, UploadApi;
import '../../domain/repositories/studio_repository.dart';
import 'mobile_style.dart';
import 'study_create_mobile.dart';

/// What a build needs from the server (the API, or a fake in tests).
abstract interface class StudyBuildBackend {
  /// Creates the studio; returns its id.
  Future<String> createStudio(String title);

  /// Uploads one file; returns its ingest job.
  Future<String> upload(String studioId, String name, Uint8List bytes);

  /// Completes when the job's file is read; throws if it could not be.
  Future<void> ingested(String studioId, String jobId);

  /// Starts generating over every file; returns the build id.
  Future<String> startBuild(String studioId);

  Future<BuildSnapshot> snapshot(String studioId, String buildId);
}

enum FileStage { queued, uploading, reading, done, failed, skipped }

/// One material on its way in.
class BuildFile {
  BuildFile(this.file);

  final SmPickedFile file;
  FileStage stage = FileStage.queued;

  /// How far along, for the overall percentage.
  double get weight => switch (stage) {
    FileStage.queued || FileStage.failed => 0,
    FileStage.uploading => 0.25,
    FileStage.reading => 0.6,
    FileStage.done || FileStage.skipped => 1,
  };
}

/// A new studio being made: created, each file uploaded and read, then
/// generated. Everything shown comes from the server; the run keeps going
/// when the page is left ("Continue in background").
class StudyBuildRun extends ChangeNotifier {
  StudyBuildRun({
    required this.backend,
    required this.title,
    required List<SmPickedFile> files,
    this.poll = const Duration(seconds: 2),
    this.studioId,
  }) : files = [for (final f in files) BuildFile(f)],
       updating = studioId != null;

  final StudyBuildBackend backend;
  final String title;
  final List<BuildFile> files;
  final Duration poll;

  /// Set from the start when files are added to a studio that exists.
  String? studioId;

  /// Adding to an existing studio (not making a new one).
  final bool updating;
  String? buildId;
  BuildSnapshot? snapshot;

  /// Set when the studio could not be made or the build failed.
  String? error;

  final _started = DateTime.now();
  final _jobs = <BuildFile, Future<void>>{};

  bool get isDone => snapshot?.isDone ?? false;
  bool get isFailed => error != null;
  bool get building => buildId != null;

  int get filesDone => files.where((f) => f.stage == FileStage.done).length;
  int get filesFailed => files.where((f) => f.stage == FileStage.failed).length;

  /// 0..1: making the studio, reading the files (a quarter), generating.
  double get progress {
    if (isDone) return 1;
    final read = files.isEmpty
        ? 1.0
        : files.fold<double>(0, (sum, f) => sum + f.weight) / files.length;
    return (studioId == null ? 0 : 0.03) +
        0.25 * read +
        0.72 * (snapshot?.progressPct ?? 0);
  }

  /// "Ingesting 2 of 6 files…", "Building lessons (3 of 8)…", "Ready".
  String get stageText {
    if (error != null) return error!;
    if (studioId == null) return 'Setting up your studio…';
    if (!building) {
      if (filesFailed > 0 && _jobs.isEmpty) {
        return filesFailed == 1
            ? 'Couldn’t read 1 file'
            : 'Couldn’t read $filesFailed files';
      }
      final total = files.where((f) => f.stage != FileStage.skipped).length;
      return 'Ingesting $filesDone of $total files…';
    }
    final s = snapshot;
    if (s == null) return 'Starting the build…';
    return switch (s.status) {
      'done' => 'Ready',
      'generating' when s.lessonsTotal > 0 =>
        'Building lessons (${s.lessonsDone} of ${s.lessonsTotal})…',
      'generating' => 'Building topics and flashcards…',
      'scenarios' => 'Adding practice scenarios…',
      'extracting' => 'Finding the key topics…',
      _ => 'Starting the build…',
    };
  }

  /// A rough time left, once there is a pace to go by.
  String get eta {
    if (isDone) return 'Your studio is ready';
    if (isFailed) return 'Try again, or come back to it later';
    final p = progress;
    final spent = DateTime.now().difference(_started).inSeconds;
    if (p < 0.08 || spent < 4) return 'Usually about a minute';
    final left = (spent / p * (1 - p)).round();
    if (left < 15) return 'Almost there';
    if (left < 60) return 'About ${(left / 10).ceil() * 10} seconds left';
    final minutes = (left / 60).round();
    return minutes <= 1 ? 'About a minute left' : 'About $minutes minutes left';
  }

  var _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    error = null;
    notifyListeners();
    try {
      studioId ??= await backend.createStudio(title);
      notifyListeners();
    } on Object {
      error = 'Couldn’t create the studio';
      _running = false;
      SmHaptics.error();
      notifyListeners();
      return;
    }
    // Upload one at a time; each is read on the server while the next goes.
    for (final f in files) {
      if (f.stage == FileStage.queued) await _send(f);
    }
    await _whenRead();
  }

  /// Sends [f] again, after it failed.
  Future<void> retry(BuildFile f) async {
    if (f.stage != FileStage.failed || studioId == null) return;
    SmHaptics.tap();
    await _send(f);
    await _whenRead();
  }

  /// Builds without [f].
  Future<void> skip(BuildFile f) async {
    if (f.stage != FileStage.failed) return;
    SmHaptics.tap();
    f.stage = FileStage.skipped;
    notifyListeners();
    await _whenRead();
  }

  /// Starts the build again, after it failed.
  Future<void> retryBuild() async {
    if (studioId == null) {
      _running = false;
      return start();
    }
    SmHaptics.tap();
    buildId = null;
    snapshot = null;
    error = null;
    notifyListeners();
    await _whenRead();
  }

  Future<void> _send(BuildFile f) async {
    f.stage = FileStage.uploading;
    notifyListeners();
    final String job;
    try {
      job = await backend.upload(studioId!, f.file.name, f.file.bytes);
    } on Object {
      _fail(f);
      return;
    }
    f.stage = FileStage.reading;
    notifyListeners();
    _jobs[f] = backend
        .ingested(studioId!, job)
        .then((_) {
          f.stage = FileStage.done;
          SmHaptics.select();
        }, onError: (Object _) => _fail(f))
        .whenComplete(() {
          _jobs.remove(f);
          notifyListeners();
        });
  }

  void _fail(BuildFile f) {
    f.stage = FileStage.failed;
    SmHaptics.error();
    notifyListeners();
  }

  /// Once every file is read (or skipped), builds.
  Future<void> _whenRead() async {
    while (_jobs.isNotEmpty) {
      await Future.wait(_jobs.values.toList());
    }
    final waiting = files.any(
      (f) => f.stage == FileStage.failed || f.stage == FileStage.uploading,
    );
    if (waiting || building || isFailed) return;
    if (filesDone == 0) {
      error = 'None of the files could be read';
      notifyListeners();
      return;
    }
    try {
      buildId = await backend.startBuild(studioId!);
    } on SseException catch (e) {
      error = e.outOfCredits ? e.message : 'Couldn’t start the build';
      SmHaptics.error();
      notifyListeners();
      return;
    } on Object {
      error = 'Couldn’t start the build';
      SmHaptics.error();
      notifyListeners();
      return;
    }
    notifyListeners();
    // Left for the background: the server builds on its own and the
    // studio's page follows it from here.
    if (!_left) await _follow();
  }

  var _misses = 0;

  Future<void> _follow() async {
    while (!_disposed && !_left) {
      try {
        snapshot = await backend.snapshot(studioId!, buildId!);
        _misses = 0;
      } on Object {
        if (++_misses >= 5) {
          error = 'Lost track of the build';
          notifyListeners();
          return;
        }
      }
      if (snapshot?.isFailed ?? false) {
        error = 'The build failed';
        SmHaptics.error();
        notifyListeners();
        return;
      }
      if (isDone) {
        SmHaptics.done();
        notifyListeners();
        return;
      }
      notifyListeners();
      await Future<void>.delayed(poll);
    }
  }

  var _disposed = false;
  var _left = false;

  /// The page closed: files still on their way keep going and the build
  /// is started, but nobody is watching it any more.
  void leave() {
    _left = true;
    if (building || isFailed) dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The build's way to the Study API.
class ApiStudyBuildBackend implements StudyBuildBackend {
  ApiStudyBuildBackend(this._studios, this._upload, {this.onStarted});

  final StudioRepository _studios;
  final UploadApi _upload;

  /// Called once a build is under way (to ask for notifications: "we'll
  /// tell you when it's ready").
  final void Function()? onStarted;

  @override
  Future<String> createStudio(String title) async =>
      (await _studios.createStudio(title: title)).id;

  @override
  Future<String> upload(String studioId, String name, Uint8List bytes) =>
      _upload.uploadDocument(studioId: studioId, filename: name, bytes: bytes);

  @override
  Future<void> ingested(String studioId, String jobId) =>
      _upload.watchBuild(studioId: studioId, jobId: jobId);

  @override
  Future<String> startBuild(String studioId) async {
    final id = await _upload.startBuild(studioId: studioId);
    onStarted?.call();
    return id;
  }

  @override
  Future<BuildSnapshot> snapshot(String studioId, String buildId) =>
      _upload.buildSnapshot(studioId: studioId, buildId: buildId);
}
