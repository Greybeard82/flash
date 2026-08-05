import 'package:flutter/material.dart';
import '../services/loading_controller.dart';

/// Thin progress bar pinned to the top of the content area, shown whenever
/// [LoadingController] is busy. Fades in after a short delay so instant
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
    final theme = Theme.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ),
      ),
    );
  }
}
