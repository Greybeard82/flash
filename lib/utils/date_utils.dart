String formatRelativeTime(DateTime? dateTime) {
  if (dateTime == null) return '';
  final now = DateTime.now();
  final diff = now.difference(dateTime);

  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '${m}m ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '${h}h ago';
  }
  if (diff.inDays < 7) {
    final d = diff.inDays;
    return d == 1 ? 'yesterday' : '${d}d ago';
  }
  if (diff.inDays < 30) {
    final w = (diff.inDays / 7).floor();
    return w == 1 ? '1 week ago' : '${w} weeks ago';
  }
  if (diff.inDays < 365) {
    final mo = (diff.inDays / 30).floor();
    return mo == 1 ? '1 month ago' : '${mo} months ago';
  }
  final y = (diff.inDays / 365).floor();
  return y == 1 ? '1 year ago' : '${y} years ago';
}

String formatRelativeTimestamp(int? millis) {
  if (millis == null) return '';
  return formatRelativeTime(DateTime.fromMillisecondsSinceEpoch(millis));
}
