import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A non-blocking banner that slides in below the app bar.
/// Only one banner is shown at a time; a new message replaces the current one.
/// Persistent banners (e.g. "Fetching…") stay until explicitly dismissed.
class NotificationBanner extends StatefulWidget {
  const NotificationBanner({super.key});

  @override
  State<NotificationBanner> createState() => NotificationBannerState();
}

class NotificationBannerState extends State<NotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;

  String? _message;
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void show(String message, {bool persistent = false}) {
    _timer?.cancel();
    setState(() {
      _message = message;
      _visible = true;
    });
    _ctrl.forward(from: 0);
    if (!persistent) {
      _timer = Timer(const Duration(seconds: 4), dismiss);
    }
  }

  void dismiss() {
    _timer?.cancel();
    _ctrl.reverse().then((_) {
      if (!mounted) return;
      // Clearing _message as well as _visible is what actually collapses the
      // banner. Leaving it set kept build()'s early-out unreachable, so the
      // Container stayed laid out at full height — merely slid off-screen by
      // the SlideTransition — and left a permanent blank strip above the
      // article list in the Column that hosts this widget.
      setState(() {
        _visible = false;
        _message = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible && _message == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SlideTransition(
      position: _slide,
      child: GestureDetector(
        onTap: dismiss,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            // Was `inverseSurface`, which is semantically right for a full
            // inversion and was the heaviest block of colour in the whole
            // light theme for what is usually a one-line confirmation. This
            // is its own role now, so `inverseSurface` keeps its meaning
            // instead of being borrowed.
            color: theme.flashColors.bannerSurface,
            // The fill sits about 1.10:1 off the page, which is deliberate —
            // the banner slides in, and motion is what catches the eye. The
            // hairline is what keeps the edge legible once it has settled.
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Text(
            _message ?? '',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
