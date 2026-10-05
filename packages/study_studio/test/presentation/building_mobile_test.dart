import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/data/api/upload_api.dart';
import 'package:study_studio/src/domain/entities/source.dart';
import 'package:study_studio/src/presentation/mobile/study_build_run.dart';
import 'package:study_studio/src/presentation/mobile/study_building_mobile.dart';
import 'package:study_studio/src/presentation/mobile/study_create_mobile.dart';

import 'home_page_test.dart' show phone, viewport;

/// A server the test moves along by hand.
class FakeBackend implements StudyBuildBackend {
  final reads = <String, Completer<void>>{};
  final failUpload = <String>{};
  var snapshots = <BuildSnapshot>[];
  var builds = 0;

  @override
  Future<String> createStudio(String title) async => 'st1';

  @override
  Future<String> upload(String studioId, String name, Uint8List bytes) async {
    if (failUpload.remove(name)) throw Exception('nope');
    reads[name] = Completer<void>();
    return name;
  }

  @override
  Future<void> ingested(String studioId, String jobId) => reads[jobId]!.future;

  @override
  Future<String> startBuild(String studioId) async {
    builds++;
    return 'b1';
  }

  @override
  Future<BuildSnapshot> snapshot(String studioId, String buildId) async =>
      snapshots.length > 1 ? snapshots.removeAt(0) : snapshots.first;
}

BuildSnapshot snap(String status, double pct) => BuildSnapshot(
  status: status,
  stage: '',
  lessonsDone: 0,
  lessonsTotal: 0,
  progressPct: pct,
);

List<SmPickedFile> picked(List<String> names) => [
  for (final n in names)
    SmPickedFile(name: n, type: smTypeFor(n), bytes: Uint8List(1024)),
];

void main() {
  late FakeBackend server;
  late StudyBuildRun run;
  var proceeded = 0;
  var left = 0;

  setUp(() {
    server = FakeBackend()..snapshots = [snap('generating', 0.5)];
    proceeded = 0;
    left = 0;
  });

  Future<void> show(WidgetTester tester, List<String> names) async {
    viewport(tester, phone);
    run = StudyBuildRun(
      backend: server,
      title: 'Networks',
      files: picked(names),
      poll: const Duration(milliseconds: 100),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StudyBuildingMobile(
          run: run,
          onProceed: () => proceeded++,
          onBackground: () => left++,
        ),
      ),
    );
    unawaited(run.start());
    await tester.pump();
    await tester.pump();
  }

  testWidgets('lists the files as they are read, then builds', (tester) async {
    await show(tester, ['Networks_ch4.pdf', 'Slides.pptx']);
    expect(find.text('Networks_ch4.pdf'), findsOne);
    expect(find.text('Reading…'), findsNWidgets(2));
    expect(find.text('Ingesting 0 of 2 files…'), findsOne);

    server.reads['Networks_ch4.pdf']!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ingesting 1 of 2 files…'), findsOne);
    expect(find.byIcon(Icons.check_circle_rounded), findsOne);

    server.reads['Slides.pptx']!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(server.builds, 1);
    expect(find.text('Building topics and flashcards…'), findsOne);
    // Two files read (a quarter) and half the build: 3 + 25 + 36.
    expect(find.text('64%', findRichText: true), findsOne);

    server.snapshots = [snap('done', 1)];
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ready'), findsOne);
    expect(find.text('Open studio'), findsOne);
    await tester.tap(find.text('Open studio'));
    expect(proceeded, 1);
    run.dispose();
  });

  testWidgets('the two ways out fade in after five seconds', (tester) async {
    await show(tester, ['a.pdf']);
    final out = find.ancestor(
      of: find.text('Continue in background'),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(out).opacity, 0);
    await tester.tap(find.text('Continue in background'), warnIfMissed: false);
    expect(left, 0);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.widget<AnimatedOpacity>(out).opacity, 1);
    expect(find.text('Proceed to studio'), findsOne);
    await tester.tap(find.text('Continue in background'));
    expect(left, 1);
    server.reads['a.pdf']!.complete();
    await tester.pump();
    run.dispose();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('a file that fails can be retried or skipped', (tester) async {
    server.failUpload.add('bad.jpg');
    await show(tester, ['good.pdf', 'bad.jpg']);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Retry'), findsOne);

    server.reads['good.pdf']!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Couldn’t read 1 file'), findsOne);
    expect(server.builds, 0); // waits for the failed one

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Reading…'), findsOne);

    server.reads['bad.jpg']!.completeError(Exception('unreadable'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Let the status finish switching.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('bad.jpg'), findsNothing);
    expect(server.builds, 1);
    expect(tester.takeException(), isNull);
    run.dispose();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
