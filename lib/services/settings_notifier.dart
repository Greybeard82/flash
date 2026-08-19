import 'package:flutter/foundation.dart';

/// Broadcast signal that a setting changed on the Settings screen.
///
/// The four main screens live in a kept-alive IndexedStack, so switching to
/// Settings and back does not rebuild or reload FeedScreen — it reads its
/// reading-behaviour settings once in `_boot()` and would otherwise keep the
/// values it started with for the rest of the session. Screens that own
/// behaviour driven by settings listen here and re-read.
class SettingsNotifier extends ChangeNotifier {
  static final SettingsNotifier instance = SettingsNotifier._();

  SettingsNotifier._();

  /// Call after persisting any setting.
  void settingsChanged() => notifyListeners();
}
