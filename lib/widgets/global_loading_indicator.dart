import 'package:flutter/material.dart';
import '../services/loading_controller.dart';
import 'spinning_refresh_icon.dart';

/// Small spinning arrow shown in the app-bar row whenever [LoadingController]
/// is busy. The same glyph as every other loading state in the app — one
/// indicator, not a linear bar here and a circle there. Fades in after a short
/// delay so instant operations don't flash, and fades out smoothly when done.
///
/// That glyph used to be a rotating app bolt, on the argument that the mark
/// and the spinner should be one shape. The bolt has been withdrawn from
/// every loading state: a mark that also means "working" cannot be read at a
/// glance, and the app already had a better picture of going round in the
/// refresh arrow. The static bolt stays a mark, and only a mark.
///
/// It sits at the top **right**, not centred. This is an overlay on the whole
/// screen stack, so a centred one landed at the very top middle of the display
/// — directly under the camera cut-out, where it was half-hidden by the punch
/// hole. The right-hand end of the app bar is the only place in the app that
/// already means "status of what is happening", and it is where the
/// background-fetch indicator lives too.
class GlobalLoadingIndicator extends StatefulWidget {
  const GlobalLoadingIndicator({super.key});

  @override
  State<GlobalLoadingIndicator> createState() => _GlobalLoadingIndicatorState();
}

class _GlobalLoadingIndicatorState extends State<GlobalLoadingIndicator> {
  bool _visible = false;
  Object? _delayToken;

  @override
  void initState() {
    super.initState();
    LoadingController.instance.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    LoadingController.instance.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final busy = LoadingController.instance.isBusy;
    if (busy) {
      final token = Object();
      _delayToken = token;
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted || _delayToken != token) return;
        if (LoadingController.instance.isBusy) setState(() => _visible = true);
      });
    } else {
      _delayToken = null;
      if (mounted) setState(() => _visible = false);
    }
  }

  /// Clears the feed screen's two app-bar actions (quick settings, filter),
  /// which are the only actions any screen puts here.
  static const double _rightInset = 112;
  static const double _size = 24;

  @override
  Widget build(BuildContext context) {
    // viewPadding, not padding: Scaffold consumes `padding` for its body, so
    // by the time this overlay is built `padding.top` can already be zero and
    // the bolt would ride up into the status bar again. viewPadding always
    // reports the real cut-out inset.
    final topInset = MediaQuery.of(context).viewPadding.top;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.only(
              // Centred in the toolbar row, so it lines up with the action
              // icons rather than floating above or below them.
              top: topInset + (kToolbarHeight - _size) / 2,
              right: _rightInset,
            ),
            child: SpinningRefreshIcon(
              size: _size,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
