import 'dart:ui';

import '../l10n/app_localizations.dart';

/// The localisations for the device's language, resolved without a
/// `BuildContext`.
///
/// Notification text is written outside the widget tree — sometimes outside
/// the UI isolate entirely, where `main()` never ran and
/// `AppLocalizations.of(context)` has no context to read.
/// `lookupAppLocalizations` is a plain constructor call over generated
/// constants (no assets, no bundle, no binding), so it is safe there; the
/// locale comes from [PlatformDispatcher] for the same reason.
///
/// Returns null rather than throwing. A refresh that fetched every feed
/// successfully must not be lost to a missing translation — callers fall back
/// to English rather than to nothing.
AppLocalizations? deviceLocalizations() {
  try {
    const supported = ['en', 'de', 'es', 'fr', 'it'];
    // The whole preferred list, not just `locale` (which is `locales.first`).
    // MaterialApp resolves with basicLocaleListResolution, which walks the
    // list — so a device set to [pt-BR, es-ES] renders the entire app in
    // Spanish while `locale` still says pt. Reading only the first would put
    // an English notification on top of a Spanish app.
    var code = 'en';
    for (final locale in PlatformDispatcher.instance.locales) {
      if (supported.contains(locale.languageCode)) {
        code = locale.languageCode;
        break;
      }
    }
    return lookupAppLocalizations(Locale(code));
  } catch (_) {
    return null;
  }
}
