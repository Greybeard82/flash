import 'package:flutter/material.dart';
import '../services/loading_controller.dart';
import 'fetching_indicator.dart';

/// Small spinning bolt pinned to the top of the content area, shown whenever
/// [LoadingController] is busy. The same glyph as every other loading state
/// in the app — one indicator, not a linear bar here and a circle there. Fades in after a short delay so instant
/// operations don't flash, and fades out smoothly when done.
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

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Center(child: FetchingIndicator(size: 24)),
        ),
      ),
    );
  }
}
