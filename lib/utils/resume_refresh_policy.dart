/// Decides whether returning to the app from the background should trigger
/// a network fetch. A DB reload always happens on resume; this policy only
/// gates the network call.
class ResumeRefreshPolicy {
  final Duration minBackgroundDuration;
  final Duration minFetchInterval;

  const ResumeRefreshPolicy({
    this.minBackgroundDuration = const Duration(seconds: 30),
    this.minFetchInterval = const Duration(minutes: 5),
  });

  bool shouldFetch({
    required DateTime? pausedAt,
    required DateTime resumedAt,
    required DateTime? lastFetchAt,
  }) {
    if (pausedAt == null) return false;
    if (pausedAt.isAfter(resumedAt)) return false;
    if (resumedAt.difference(pausedAt) < minBackgroundDuration) return false;
    if (lastFetchAt != null) {
      if (lastFetchAt.isAfter(resumedAt)) return false;
      if (resumedAt.difference(lastFetchAt) < minFetchInterval) return false;
    }
    return true;
  }
}
