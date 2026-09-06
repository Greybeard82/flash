import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// The 1x1 home screen widget's copy of the unread count.
///
/// Deliberately thinner than [UnreadBadgeService]: there is no launcher to
/// probe and no fallback to arrange. `updateWidget` broadcasts to a provider
/// that may have no instances placed, which is a no-op — so this does not need
/// to know, or ask, whether the user has actually put the widget anywhere.
///
/// It is driven from inside `UnreadBadgeService.update`, not from that
/// service's callers. The count the widget shows is then the same number the
/// launcher badge is showing, written in the same breath, and there is no
/// second path that could be added at one call site and forgotten at another.
class UnreadWidgetService {
  static final UnreadWidgetService instance = UnreadWidgetService._();

  UnreadWidgetService._();

  /// Must match `UnreadWidgetProvider.KEY_COUNT`.
  static const _dataKey = 'unread_count';

  /// Resolved by home_widget against the application id, so this is
  /// `io.getflash.app.UnreadWidgetProvider`.
  static const _androidProviderName = 'UnreadWidgetProvider';

  /// The last value pushed, so an unchanged count does not broadcast.
  ///
  /// The badge is rewritten on every read, every refresh and every
  /// mark-read-on-scroll flush. Each push here is a platform channel round
  /// trip plus a broadcast the launcher has to wake for and re-render from, so
  /// sending one for a number that has not moved is pure waste.
  int? _pushed;

  /// Forgets the last pushed value, so each test starts from nothing.
  @visibleForTesting
  void debugReset() => _pushed = null;

  Future<void> update(int count) async {
    final safe = count < 0 ? 0 : count;
    if (_pushed == safe) return;

    // Swallowed on purpose. This runs at the top of
    // UnreadBadgeService.update, so anything thrown here — a missing plugin, a
    // launcher that rejects the broadcast — would take the launcher badge and
    // the notification down with it. The widget is the least important of the
    // three and must not be able to break the other two.
    try {
      await HomeWidget.saveWidgetData<int>(_dataKey, safe);
      await HomeWidget.updateWidget(androidName: _androidProviderName);
      _pushed = safe;
    } catch (_) {
      // Left unrecorded so the next update retries rather than assuming the
      // widget already shows this number.
      _pushed = null;
    }
  }
}
