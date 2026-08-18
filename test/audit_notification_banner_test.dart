// AUDIT HANDOFF — Bug finding C3. Expected to FAIL until fixed.
//
// NotificationBannerState.build() bails out early only when
// `!_visible && _message == null`. dismiss() sets _visible = false but never
// clears _message, so after the first banner is ever shown the guard can
// never be true again: the Container keeps being built and laid out at full
// height, merely translated off-screen by the SlideTransition.
//
// In FeedScreen the banner sits in a Column above the article list, so the
// dismissed banner leaves a permanent empty strip pushing the list down for
// the rest of the session.
//
// Widget test with no DB involvement — NotificationBanner is self-contained.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/widgets/notification_banner.dart';

void main() {
  testWidgets('baseline: an un-shown banner takes up no vertical space',
      (tester) async {
    final key = GlobalKey<NotificationBannerState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [NotificationBanner(key: key)]),
      ),
    ));
    await tester.pump();

    expect(tester.getSize(find.byType(NotificationBanner)).height, 0.0);
  });

  testWidgets('baseline: a shown banner does take up vertical space',
      (tester) async {
    final key = GlobalKey<NotificationBannerState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [NotificationBanner(key: key)]),
      ),
    ));
    key.currentState!.show('All marked read');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.getSize(find.byType(NotificationBanner)).height,
        greaterThan(0.0));
    expect(find.text('All marked read'), findsOneWidget);
  });

  testWidgets('FAILING (C3): after auto-dismiss the banner collapses back to '
      'zero height instead of leaving a permanent gap', (tester) async {
    final key = GlobalKey<NotificationBannerState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [NotificationBanner(key: key)]),
      ),
    ));

    key.currentState!.show('All marked read');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // The 4s auto-dismiss timer fires, then the 200ms slide-out completes.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(NotificationBanner)).height,
      0.0,
      reason: 'dismiss() never clears _message, so build() keeps laying the '
          'banner out at full height (just slid off-screen) — in FeedScreen '
          'that is a permanent blank strip above the article list',
    );
  });

  testWidgets('FAILING (C3): after an explicit tap-to-dismiss the banner also '
      'collapses to zero height', (tester) async {
    final key = GlobalKey<NotificationBannerState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [NotificationBanner(key: key)]),
      ),
    ));

    key.currentState!.show('All marked read', persistent: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    key.currentState!.dismiss();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(NotificationBanner)).height, 0.0,
        reason: 'same root cause as the auto-dismiss case');
  });
}
