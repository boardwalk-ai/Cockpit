import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/src/domain/card_schedule.dart';
import 'package:study_studio/src/domain/entities/flashcard.dart';

/// The same table as the server's `test_schedule_follows_the_table`.
const cases = [
  // (reps, interval, ease, lapses), grade, (reps, interval, ease, lapses), wait
  ((0, 0.0, 2.5, 0), 0, (0, 0.0, 2.3, 1), Duration(minutes: 1)),
  ((0, 0.0, 2.5, 0), 1, (0, 0.0, 2.35, 0), Duration(minutes: 10)),
  ((0, 0.0, 2.5, 0), 2, (1, 1.0, 2.5, 0), Duration(days: 1)),
  ((0, 0.0, 2.5, 0), 3, (1, 4.0, 2.65, 0), Duration(days: 4)),
  ((1, 1.0, 2.5, 0), 2, (2, 3.0, 2.5, 0), Duration(days: 3)),
  ((2, 3.0, 2.5, 0), 2, (3, 7.5, 2.5, 0), Duration(hours: 180)),
  ((2, 3.0, 2.5, 0), 1, (3, 3.6, 2.35, 0), Duration(minutes: 5184)),
  ((2, 3.0, 2.5, 0), 3, (3, 9.75, 2.65, 0), Duration(minutes: 14040)),
  ((3, 7.5, 1.35, 1), 0, (0, 0.0, 1.3, 2), Duration(minutes: 1)),
  ((3, 7.5, 2.95, 0), 3, (4, 28.7625, 3.0, 0), Duration(seconds: 2485080)),
];

void main() {
  final now = DateTime.utc(2026, 10, 6, 9);

  test('follows the same table as the server', () {
    for (final (before, grade, after, wait) in cases) {
      final card = Flashcard(
        id: 'c',
        topicId: 't',
        front: '',
        back: '',
        reps: before.$1,
        intervalDays: before.$2,
        ease: before.$3,
        lapses: before.$4,
      );
      final next = CardSchedule.review(card, grade, now);
      final why = '$before grade $grade';
      expect(next.reps, after.$1, reason: why);
      expect(next.intervalDays, closeTo(after.$2, 1e-9), reason: why);
      expect(next.ease, closeTo(after.$3, 1e-9), reason: why);
      expect(next.lapses, after.$4, reason: why);
      expect(next.dueDate!.difference(now), wait, reason: why);
    }
  });

  test('labels say when the card comes back', () {
    const fresh = Flashcard(id: 'c', topicId: 't', front: '', back: '');
    expect(
      [for (var g = 0; g < 4; g++) CardSchedule.wait(fresh, g, now)],
      ['1 min', '10 min', '1 day', '4 days'],
    );
    expect(CardSchedule.label(const Duration(hours: 5)), '5 h');
    expect(CardSchedule.label(const Duration(days: 62)), '2 mo');
  });

  test('new and overdue cards are due', () {
    const fresh = Flashcard(id: 'c', topicId: 't', front: '', back: '');
    expect(CardSchedule.isDue(fresh, now), isTrue);
    final later = CardSchedule.review(fresh, 2, now);
    expect(CardSchedule.isDue(later, now), isFalse);
    expect(CardSchedule.isDue(later, now.add(const Duration(days: 1))), isTrue);
  });
}
