/// "Today" / "Yesterday" / "3 days ago" / date.
String relativeDay(DateTime? date) {
  if (date == null) return 'Never';
  final now = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return '$diff days ago';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
