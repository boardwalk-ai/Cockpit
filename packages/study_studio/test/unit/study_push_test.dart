import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/application/study_push.dart';
import 'package:study_studio/src/domain/study_plan.dart';

import '../helpers/fake_studio_repository.dart';

class _FakePush implements StudyPush {
  _FakePush({this.allowed = false, this.allowOnAsk = true});

  bool allowed;
  final bool allowOnAsk;
  final refreshes = StreamController<String>.broadcast();
  var asked = 0;

  @override
  String get platform => 'android';

  @override
  Future<String> deviceId() async => 'device-1';

  @override
  Future<String?> token({required bool ask}) async {
    if (ask) {
      asked++;
      if (allowOnAsk) allowed = true;
    }
    return allowed ? 'tok-1' : null;
  }

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;
}

void main() {
  group('PlanSettings reminder', () {
    test('kept apart from the plan key, off survives a round trip', () {
      const s = PlanSettings(minutes: 45, days: {1, 3});
      expect(s.remind, PlanSettings.defaultRemind);
      final off = s.copyWith(remindOff: true);
      expect(off.remind, isNull);
      expect(off.planKey(), s.planKey());
      expect(PlanSettings.decode(off.encode())!.remind, isNull);
      expect(PlanSettings.decode(s.copyWith(remind: 420).encode())!.remind, 420);
    });

    test('plans saved before reminders get 7 PM', () {
      final old = PlanSettings.decode(
        '{"mode":"pace","minutes":30,"days":[1,2]}',
      )!;
      expect(old.remind, 19 * 60);
      expect(old.planKey(), '{"mode":"pace","minutes":30,"days":[1,2]}');
    });

    test('what the server gets', () {
      final s = PlanSettings(
        mode: PlanMode.exam,
        exam: DateTime(2026, 11, 2),
        days: const {5, 1},
        remind: 1140,
      );
      expect(s.toApi(390), {
        'mode': 'exam',
        'exam': '2026-11-02',
        'minutes': 30,
        'days': [1, 5],
        'remind': 1140,
        'tzMinutes': 390,
      });
    });
  });

  group('StudyPushLink', () {
    test('registers only when allowed, without asking on start', () async {
      final repo = FakeStudioRepository();
      final push = _FakePush();
      final link = StudyPushLink(push, () => repo, tzMinutes: () => 390)
        ..start();
      await pumpEventQueue();
      expect(push.asked, 0);
      expect(repo.devices, isEmpty);

      await link.sync(ask: true);
      expect(push.asked, 1);
      expect(repo.devices, {'device-1': 'tok-1'});

      push.refreshes.add('tok-2');
      await pumpEventQueue();
      expect(repo.devices, {'device-1': 'tok-2'});

      await link.unregister();
      expect(repo.devices, isEmpty);
      link.dispose();
    });

    test('a chosen reminder asks for notifications; a loaded one does not',
        () async {
      final repo = FakeStudioRepository();
      final push = _FakePush();
      final link = StudyPushLink(push, () => repo, tzMinutes: () => 0);
      await link.savePlan('s1', const PlanSettings(), chosen: false);
      expect(push.asked, 0);
      expect(repo.plans['s1']!['remind'], 19 * 60);
      await link.savePlan(
        's1',
        const PlanSettings().copyWith(remindOff: true),
        chosen: true,
      );
      expect(push.asked, 0);
      await link.savePlan('s1', const PlanSettings(), chosen: true);
      expect(push.asked, 1);
      expect(repo.devices, {'device-1': 'tok-1'});
    });
  });
}
