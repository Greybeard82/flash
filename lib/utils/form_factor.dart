import 'package:flutter/services.dart';

/// The one method channel to the host Activity.
const MethodChannel deviceChannel = MethodChannel('io.getflash.app/device');

/// Tells the Activity what colour to paint the window behind the Flutter
/// surface, and persists it natively for the next cold start.
///
/// The window background must track the *app's* theme, not the OS uiMode:
/// with the app set to Dark and the OS in light mode, the old uiMode-derived
/// logic painted white, which leaked through wherever the Flutter surface
/// didn't fully cover — most visibly as a washed-out launch and white edges
/// on overscroll.
Future<void> setNativeWindowBackground(Color color) async {
  final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  try {
    await deviceChannel.invokeMethod<void>('setWindowBackground', {'color': hex});
  } catch (_) {
    // Non-Android host, or the Activity isn't up yet — purely cosmetic.
  }
}

/// Detects the device form factor at startup (phone / tablet / TV).
///
/// Call [FormFactor.init()] once in main() before runApp so that [isTV] is
/// available synchronously everywhere in the widget tree.
class FormFactor {
  FormFactor._();

  static const _channel = deviceChannel;
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
