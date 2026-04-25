import 'package:flutter/services.dart';

/// Detects the device form factor at startup (phone / tablet / TV).
///
/// Call [FormFactor.init()] once in main() before runApp so that [isTV] is
/// available synchronously everywhere in the widget tree.
class FormFactor {
  FormFactor._();

  static const _channel = MethodChannel('io.getflash.app/device');
  static bool _isTV = false;

  /// Must be awaited in main() before runApp.
  static Future<void> init() async {
    try {
      _isTV = await _channel.invokeMethod<bool>('isTV') ?? false;
    } catch (_) {
      _isTV = false;
    }
  }

  /// True when the app is running on an Android TV / Google TV device.
  static bool get isTV => _isTV;
}
