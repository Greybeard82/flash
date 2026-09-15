import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A non-blocking banner that slides in below the app bar.
/// Only one banner is shown at a time; a new message replaces the current one.
/// Persistent banners (e.g. "Fetching…") stay until explicitly dismissed.
/// What a banner is reporting.
///
/// The widget carries 18 distinct messages and they split almost evenly: ten
/// say something the reader asked for happened, eight say it did not. Before
/// this they were the same strip in the same colour, so "Backup saved" and
/// "Not a valid Flash backup file" were told apart only by reading them
/// before they slid away after four seconds.
///
/// **The split is carried by the glyph, never by colour.** No red is
/// introduced: in Quiet Ink red means exactly one thing (broken) and in
/// Newspaper it is the spot colour already doing four other jobs. Both
/// variants take `primary`, so the icon reads as part of the component in
/// every theme and only its shape changes.
enum BannerKind {
  /// It happened.
  confirmation,

  /// It did not happen, or there was nothing to do.
  failure,
}

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
  BannerKind _kind = BannerKind.confirmation;
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

  /// Shows [message].
  ///
  /// [kind] defaults to a confirmation because that is the larger half and
  /// because a miscategorised confirmation is the harmless direction: a
  /// failure wearing a tick is misleading, a confirmation wearing a tick is
  /// merely unremarkable.
  void show(
    String message, {
    bool persistent = false,
    BannerKind kind = BannerKind.confirmation,
  }) {
    _timer?.cancel();
    setState(() {
      _message = message;
      _kind = kind;
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
            // `bannerBorder`, not `outlineVariant`. With a fill this quiet
            // the border IS the component's edge, which makes it a graphical
            // object under WCAG 1.4.11 at 3:1 against both the fill and the
            // page. outlineVariant measures 1.08 / 1.19 and cannot carry it.
            border: Border(
              bottom: BorderSide(
                color: theme.flashColors.bannerBorder,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // A saturated glyph is visible on a pale fill in a way a pale
              // fill is not visible on a pale page. This is what makes the
              // banner findable at arm's length; the fill alone was not.
              Icon(
                _kind == BannerKind.confirmation
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                size: 17,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
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
            ],
          ),
        ),
      ),
    );
  }
}
