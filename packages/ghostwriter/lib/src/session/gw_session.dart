import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/gw_api.dart';
import '../data/ids.dart';
import 'timeline.dart';

class GwProject {
  const GwProject({
    required this.id,
    required this.title,
    required this.status,
    required this.wordCount,
    this.targetWords,
    this.folderId,
    this.updatedAt,
  });

  factory GwProject.fromJson(Map<String, dynamic> j) => GwProject(
    id: j['id'].toString(),
    title: j['title']?.toString() ?? 'Untitled essay',
    status: j['status']?.toString() ?? 'idle',
    wordCount: (j['wordCount'] as num?)?.toInt() ?? 0,
    targetWords: (j['targetWords'] as num?)?.toInt(),
    folderId: j['folderId']?.toString(),
    updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? ''),
  );

  final String id;
  final String title;

  /// `idle`, `writing` or `ready`.
  final String status;
  final int wordCount;
  final int? targetWords;
  final String? folderId;
  final DateTime? updatedAt;
}

class GwFolder {
  const GwFolder({required this.id, required this.name});

  factory GwFolder.fromJson(Map<String, dynamic> j) =>
      GwFolder(id: j['id'].toString(), name: j['name']?.toString() ?? '');

  final String id;
  final String name;
}

/// Everything the GhostWriter screens show, and every action they take. Both
/// the phone and the desktop UI sit on one of these.
///
/// A run is followed over SSE; when the connection drops it reconnects from
/// the last `seq` it saw, so nothing is missed or shown twice.
class GwSession extends ChangeNotifier {
  GwSession(this.api, {this.retryDelays = _defaultDelays});

  final GwApi api;

  /// Waits between reconnect attempts; the last one repeats.
  final List<Duration> retryDelays;

  static const _defaultDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  // ── Account and library ──────────────────────────────────────────────────

  String? userName;
  int? credits;
  List<GwProject> projects = const [];
  List<GwFolder> folders = const [];
  bool loadingLibrary = false;
  String? libraryError;

  // ── The open project ─────────────────────────────────────────────────────

  String? projectId;
  String? runId;
  String title = '';

  /// The open run. Earlier runs on the project (the first essay, then each
  /// revision) are in [earlier], oldest first.
  RunTimeline timeline = RunTimeline();
  List<RunTimeline> earlier = [];

  /// Every run's items, oldest first: the whole conversation.
  List<TimelineItem> get items => [
    for (final run in earlier) ...run.items,
    ...timeline.items,
  ];

  /// The newest sources any run found (for the Sources pill).
  List<Map<String, dynamic>>? get sources {
    for (final run in [timeline, ...earlier.reversed]) {
      if (run.sources != null) return run.sources;
    }
    return null;
  }

  int get sourceCount {
    for (final run in [timeline, ...earlier.reversed]) {
      if (run.sources != null) return run.sourceCount;
    }
    return 0;
  }

  /// Some run has written into the document (the Open Editor pill).
  bool get hasEssay =>
      timeline.writing != null || earlier.any((run) => run.writing != null);

  /// The essay is written and no run is going: what the user types now asks
  /// for a revision.
  bool get canRevise =>
      projectId != null && timeline.ended && hasEssay && !starting;

  /// True between Start and the run being created.
  bool starting = false;

  /// The live connection is down and being retried.
  bool reconnecting = false;

  /// The last action that failed (start, answer, send), for a retry banner.
  String? actionError;

  bool get hasProject => projectId != null;

  /// Bumped whenever the open run changes, so an old connection loop stops.
  int _generation = 0;
  bool _disposed = false;

  /// The brief of a start that failed, for [retry].
  String? _failedStart;
  bool _failedCreate = true;

  /// The app is in the background: the run is not followed, so the server
  /// knows to notify instead.
  bool _suspended = false;

  /// Called each time a run has started on the server.
  void Function()? onRunStarted;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  Completer<void>? _connection;

  /// The generation whose run is being followed, if any.
  int? _followingGeneration;

  GwProject? get currentProject {
    for (final p in projects) {
      if (p.id == projectId) return p;
    }
    return null;
  }

  /// Loads the account and the project list.
  Future<void> load() async {
    loadingLibrary = true;
    libraryError = null;
    _notify();
    try {
      final results = await Future.wait([api.me(), api.projects()]);
      final me = results[0];
      userName = me['name']?.toString();
      credits = (me['octoCredits'] as num?)?.toInt();
      _setLibrary(results[1]);
    } catch (e) {
      libraryError = e is GwApiException && e.code == 'account_required'
          ? 'This Google account has no Octopilot account yet. '
                'Sign up at octopilotai.app, then come back.'
          : 'Could not load your essays: ${_describe(e)}';
    } finally {
      loadingLibrary = false;
      _notify();
    }
  }

  Future<void> refreshLibrary() async {
    try {
      _setLibrary(await api.projects());
      _notify();
    } catch (_) {
      // The list is a convenience; the open project keeps working.
    }
  }

  void _setLibrary(Map<String, dynamic> data) {
    projects = [
      for (final p in data['projects'] as List? ?? const [])
        if (p is Map<String, dynamic>) GwProject.fromJson(p),
    ];
    folders = [
      for (final f in data['folders'] as List? ?? const [])
        if (f is Map<String, dynamic>) GwFolder.fromJson(f),
    ];
  }

  /// Forgets the account and its essays (after sign-out).
  void signedOut() {
    newChat();
    userName = null;
    credits = null;
    projects = const [];
    folders = const [];
    libraryError = null;
    _notify();
  }

  /// Back to the landing screen.
  void newChat() {
    _generation++;
    _stopFollowing();
    _failedStart = null;
    projectId = null;
    runId = null;
    title = '';
    timeline = RunTimeline();
    earlier = [];
    starting = false;
    reconnecting = false;
    actionError = null;
    _notify();
  }

  /// Creates a project for [brief] and starts writing it.
  Future<void> start(String brief) async {
    final text = brief.trim();
    if (text.isEmpty || starting) return;
    newChat();
    projectId = newId();
    runId = newId();
    title = text.length > 80 ? text.substring(0, 80) : text;
    starting = true;
    // Shown at once; the server's own `user_message` takes its place.
    timeline.items.add(UserItem(text));
    _notify();
    await _startRun(text);
  }

  /// Asks for a change to the written essay: a new run on the same project,
  /// shown below the earlier ones.
  Future<void> revise(String request) async {
    final text = request.trim();
    if (text.isEmpty || !canRevise) return;
    earlier = [...earlier, timeline];
    timeline = RunTimeline();
    runId = newId();
    starting = true;
    actionError = null;
    timeline.items.add(UserItem(text));
    _notify();
    await _startRun(text, create: false);
  }

  Future<void> _startRun(String brief, {bool create = true}) async {
    final project = projectId!, run = runId!;
    final generation = _generation;
    try {
      if (create) await api.putProject(project, instruction: brief);
      await api.startRun(project, run, brief);
    } catch (e) {
      if (generation != _generation) return;
      starting = false;
      _failedStart = brief;
      _failedCreate = create;
      actionError = 'Could not start: ${_describe(e)}';
      _notify();
      return;
    }
    if (generation != _generation) return;
    starting = false;
    _failedStart = null;
    _notify();
    onRunStarted?.call();
    unawaited(refreshLibrary());
    unawaited(_follow(run, generation));
  }

  /// Retries whatever failed last: the start, or the connection.
  Future<void> retry() async {
    actionError = null;
    final brief = _failedStart;
    if (brief != null) {
      // The same ids again: if the first try did reach the server, this is
      // a no-op there.
      starting = true;
      _notify();
      return _startRun(brief, create: _failedCreate);
    }
    _notify();
    reconnect();
  }

  /// Opens a project from the list and replays its latest run.
  Future<void> openProject(String id) async {
    newChat();
    projectId = id;
    final project = currentProject;
    title = project?.title ?? '';
    _notify();
    final generation = _generation;
    try {
      final data = await api.project(id);
      if (generation != _generation) return;
      title = data['title']?.toString() ?? title;
      final runs = [
        for (final id in data['runIds'] as List? ?? const []) id.toString(),
      ];
      final last = (data['lastRunId'] ?? data['activeRunId'])?.toString();
      if (runs.isEmpty && last != null) runs.add(last);
      // Earlier runs are over: replay them whole, then follow the last.
      final finished = runs.isEmpty
          ? <String>[]
          : runs.sublist(0, runs.length - 1);
      for (final run in finished) {
        final replayed = await _replay(run);
        if (generation != _generation) return;
        earlier = [...earlier, replayed];
        _notify();
      }
      runId = runs.isEmpty ? null : runs.last;
      _notify();
      if (runId != null) unawaited(_follow(runId!, generation));
    } catch (e) {
      if (generation != _generation) return;
      actionError = 'Could not open this essay: ${_describe(e)}';
      _notify();
    }
  }

  /// A finished run's whole timeline, read from its stored events.
  Future<RunTimeline> _replay(String run) async {
    final replayed = RunTimeline();
    try {
      await for (final event in api.runEvents(run)) {
        replayed.apply(event);
      }
    } catch (_) {
      // Show what arrived; the rest of the conversation still works.
    }
    return replayed;
  }

  /// Follows the open run again if its connection is down (the app came
  /// back to the foreground, or the user tapped retry).
  void reconnect() {
    _suspended = false;
    final run = runId;
    if (run == null || timeline.ended || _followingGeneration == _generation) {
      return;
    }
    unawaited(_follow(run, _generation));
  }

  bool _current(int generation) => generation == _generation && !_disposed;

  Future<void> _follow(String run, int generation) async {
    if (_followingGeneration == generation) return;
    _followingGeneration = generation;
    var attempt = 0;
    try {
      while (_current(generation)) {
        Object? failure;
        final connection = _connection = Completer<void>();
        void end() {
          if (!connection.isCompleted) connection.complete();
        }

        _subscription = api
            .runEvents(run, sinceSeq: timeline.lastSeq)
            .listen(
              (event) {
                if (!_current(generation)) return;
                attempt = 0;
                reconnecting = false;
                _dropOptimisticBrief(event);
                if (timeline.apply(event)) _onEvent(event);
                _notify();
              },
              onError: (Object e) {
                failure = e;
                end();
              },
              onDone: end,
              cancelOnError: true,
            );
        await connection.future;
        if (!_current(generation) || timeline.ended || _suspended) return;

        final error = failure;
        if (error is GwApiException &&
            (error.status == 401 ||
                error.status == 403 ||
                error.status == 404)) {
          // Not ours, or gone: nothing to wait for.
          actionError = error.message;
          reconnecting = false;
          _notify();
          return;
        }
        reconnecting = true;
        _notify();
        await Future<void>.delayed(
          retryDelays[attempt.clamp(0, retryDelays.length - 1)],
        );
        attempt++;
      }
    } finally {
      if (_followingGeneration == generation) _followingGeneration = null;
      if (_current(generation) && timeline.ended && reconnecting) {
        reconnecting = false;
        _notify();
      }
    }
  }

  /// Stops following the open run without closing it: the app went to the
  /// background. [reconnect] picks it up again from where it was.
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    _stopFollowing();
  }

  void _stopFollowing() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    final connection = _connection;
    _connection = null;
    if (connection != null && !connection.isCompleted) connection.complete();
  }

  /// The brief shown on Start stands in until the run's first event, which
  /// is the same message from the server.
  void _dropOptimisticBrief(Map<String, dynamic> event) {
    if (timeline.lastSeq == 0 &&
        event['type'] == 'user_message' &&
        timeline.items.length == 1 &&
        timeline.items.first is UserItem) {
      timeline.items.clear();
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'credits':
        credits = timeline.credits ?? credits;
      case 'done' || 'fatal' || 'cancelled':
        unawaited(refreshLibrary());
      case 'context_update':
        // The plan names the essay.
        final topic = event['essayTopic']?.toString();
        if (topic != null && topic.isNotEmpty) title = topic;
    }
  }

  /// Answers the pending question.
  Future<void> answer(String field, Object value) async {
    final run = runId;
    if (run == null) return;
    actionError = null;
    try {
      await api.answer(run, field, value);
    } on GwApiException catch (e) {
      // Already answered (another device, a double tap): the stream has it.
      if (e.code != 'no_pending_question') actionError = e.message;
    } catch (e) {
      actionError = 'Could not send your answer: ${_describe(e)}';
    }
    _notify();
  }

  /// What the chat box sends. While the focus question is open, a message
  /// asks for new options instead (as on the web); a text or number question
  /// takes it as the answer; otherwise it is a chat message.
  Future<void> send(String text) async {
    final message = text.trim();
    final run = runId;
    if (message.isEmpty || run == null) return;
    if (canRevise) return revise(message);
    final question = timeline.pending;
    if (question != null) {
      if (question.field == 'essayFocus') {
        return answer(question.field, '__chat_refinement__:$message');
      }
      if (question.inputType == 'text') return answer(question.field, message);
      if (question.inputType == 'number') {
        final n = num.tryParse(message.replaceAll(',', ''));
        if (n != null) return answer(question.field, n);
      }
    }
    actionError = null;
    try {
      await api.message(run, message);
    } on GwApiException catch (e) {
      actionError = e.code == 'run_ended'
          ? 'This run has finished. Start a new essay to keep going.'
          : e.message;
    } catch (e) {
      actionError = 'Could not send: ${_describe(e)}';
    }
    _notify();
  }

  /// Stops the run. The stream reports `cancelled`.
  Future<void> cancel() async {
    final run = runId;
    if (run == null || timeline.ended) return;
    try {
      await api.cancel(run);
    } catch (e) {
      actionError = 'Could not stop: ${_describe(e)}';
      _notify();
    }
  }

  // ── Library actions ──────────────────────────────────────────────────────

  Future<void> createFolder(String name) async {
    await api.putFolder(newId(), name.trim());
    await refreshLibrary();
  }

  Future<void> moveToFolder(String projectId, String? folderId) async {
    await api.putProject(
      projectId,
      folderId: folderId,
      unfile: folderId == null,
    );
    await refreshLibrary();
  }

  Future<void> deleteProject(String id) async {
    await api.deleteProject(id);
    if (id == projectId) newChat();
    await refreshLibrary();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _describe(Object e) =>
      e is GwApiException ? e.message : 'check your connection and try again';

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _stopFollowing();
    super.dispose();
  }
}
