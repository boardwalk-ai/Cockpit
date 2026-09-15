/// Date formatting for the front matter — ports the web `getDate` /
/// `getDateDayMonthYear`. Best-effort: parse the user's free-text date and
/// render it in the style's convention, else pass it through unchanged.
abstract final class DocDates {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// APA / Chicago: "June 12, 2026".
  static String monthDayYear(String raw) {
    final d = _parse(raw);
    if (d == null) return raw.trim();
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// MLA: "12 June 2026".
  static String dayMonthYear(String raw) {
    final d = _parse(raw);
    if (d == null) return raw.trim();
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  static DateTime? _parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    // "12 June 2026"
    final dmy = RegExp(r'^(\d{1,2})\s+([A-Za-z]+),?\s+(\d{4})$').firstMatch(s);
    if (dmy != null) {
      final mi = _months.indexWhere(
          (m) => m.toLowerCase() == dmy.group(2)!.toLowerCase());
      if (mi >= 0) {
        return DateTime(int.parse(dmy.group(3)!), mi + 1, int.parse(dmy.group(1)!));
      }
    }
    // "June 12, 2026"
    final mdy = RegExp(r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$').firstMatch(s);
    if (mdy != null) {
      final mi = _months.indexWhere(
          (m) => m.toLowerCase() == mdy.group(1)!.toLowerCase());
      if (mi >= 0) {
        return DateTime(int.parse(mdy.group(3)!), mi + 1, int.parse(mdy.group(2)!));
      }
    }
    return DateTime.tryParse(s);
  }
}
