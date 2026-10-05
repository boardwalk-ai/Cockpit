import 'entities/flashcard.dart';

/// Spaced repetition for flashcards — a port of the server's
/// `services/schedule.py` (both are tested against the same table), so each
/// rating button can say exactly when the card comes back.
///
///   0 Again  back in 1 minute (this session); ease -0.20; starts over
///   1 Hard   new: back in 10 minutes; else interval x1.2 (min 1 day)
///   2 Good   new: 1 day; second: 3 days; then interval x ease
///   3 Easy   new: 4 days; then interval x ease x 1.3; ease +0.15
abstract final class CardSchedule {
  static const minEase = 1.3;
  static const maxEase = 3.0;

  static double _ease(double v) =>
      (v.clamp(minEase, maxEase) * 100).roundToDouble() / 100;

  /// The card after a review graded [grade] (0-3), due [now] plus the wait.
  static Flashcard review(Flashcard card, int grade, DateTime now) {
    final g = grade.clamp(0, 3);
    late final int reps;
    late final double interval;
    late final double ease;
    var lapses = card.lapses;
    late final Duration wait;
    switch (g) {
      case 0:
        reps = 0;
        interval = 0;
        ease = _ease(card.ease - 0.20);
        lapses++;
        wait = const Duration(minutes: 1);
      case 1 when card.reps == 0:
        reps = 0;
        interval = 0;
        ease = _ease(card.ease - 0.15);
        wait = const Duration(minutes: 10);
      case 1:
        reps = card.reps + 1;
        interval = (card.intervalDays * 1.2) < 1 ? 1 : card.intervalDays * 1.2;
        ease = _ease(card.ease - 0.15);
        wait = _days(interval);
      case 2:
        reps = card.reps + 1;
        interval = switch (card.reps) {
          0 => 1,
          1 => 3,
          _ => _atLeastOne(card.intervalDays * card.ease),
        };
        ease = card.ease;
        wait = _days(interval);
      default:
        reps = card.reps + 1;
        interval = card.reps == 0
            ? 4
            : _atLeastOne(card.intervalDays * card.ease * 1.3);
        ease = _ease(card.ease + 0.15);
        wait = _days(interval);
    }
    return card.copyWith(
      reps: reps,
      intervalDays: interval,
      ease: ease,
      lapses: lapses,
      dueDate: now.add(wait),
      status: reps >= 2 ? FlashcardStatus.review : FlashcardStatus.learning,
    );
  }

  static double _atLeastOne(double v) => v < 1 ? 1 : v;

  static Duration _days(double days) =>
      Duration(microseconds: (days * Duration.microsecondsPerDay).round());

  /// How long until [card] would come back after [grade]: "1 min", "10 min",
  /// "3 h", "1 day", "4 days", "2 mo".
  static String wait(Flashcard card, int grade, DateTime now) =>
      label(review(card, grade, now).dueDate!.difference(now));

  static String label(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    final days = (d.inMinutes / Duration.minutesPerDay).round();
    if (days < 30) return days == 1 ? '1 day' : '$days days';
    final months = (days / 30).round();
    return months < 12 ? '$months mo' : '${(days / 365).toStringAsFixed(1)} y';
  }

  /// New, or due by [now].
  static bool isDue(Flashcard card, DateTime now) =>
      card.dueDate == null || !card.dueDate!.isAfter(now);
}
