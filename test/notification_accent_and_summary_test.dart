// B7, B8 and §1.3's accent, which between them are the parts of pass 9 a host
// suite can actually reach.
//
// **What is real here and what is not.** Nothing below posts a notification:
// `flutter_local_notifications` resolves its Android implementation from
// `Platform.isAndroid`, which is false in a host run, and touching it throws a
// LateInitializationError before any of the logic worth checking executes.
// What these assert are the *values* and the *call sites* — the accent's
// measured contrast, which channel each notification names, which importance
// each declares, and that the summary creates its channel before posting into
// it. Whether the shade actually collapses two alerts into one heading is a
// device question and is on the morning list.
//
// That split is the point rather than an apology. The contrast figures and the
// channel ids are exactly the things that rot silently in a file nobody opens;
// the stacking behaviour is the thing a person notices in one glance.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/services/notification_group.dart';

double _luminance(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel((c.r * 255).roundToDouble()) +
      0.7152 * channel((c.g * 255).roundToDouble()) +
      0.0722 * channel((c.b * 255).roundToDouble());
}

double _contrast(Color a, Color b) {
  final x = _luminance(a);
  final y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// The three surfaces 1.3 measured against: a light shade, a dark shade, and
/// the slightly lighter card a notification is drawn on inside a dark shade.
const _surfaces = <String, Color>{
  'light shade #FFFFFF': Color(0xFFFFFFFF),
  'dark shade #1B1B1B': Color(0xFF1B1B1B),
  'shade card #1F2223': Color(0xFF1F2223),
};

/// A file with its comment lines removed.
String _code(String source) => const LineSplitter()
    .convert(source)
    .where((l) => !l.trimLeft().startsWith('//'))
    .join(' ');

void main() {
  group('the accent', () {
    test('is #15868E, and measures what 1.3 says it measures', () {
      // Verified independently rather than copied across. If these three ever
      // disagree with the handoff, one of the two is wrong and the difference
      // is the thing to look at — not something to quietly re-record.
      expect(kFlashNotificationAccent, const Color(0xFF15868E));

      const expected = <String, double>{
        'light shade #FFFFFF': 4.35,
        'dark shade #1B1B1B': 3.96,
        'shade card #1F2223': 3.69,
      };
      _surfaces.forEach((name, bg) {
        expect(_contrast(kFlashNotificationAccent, bg),
            closeTo(expected[name]!, 0.01),
            reason: name);
      });
    });

    test('clears 3:1 everywhere, which is the applicable bar', () {
      // A tinted small icon is a graphical object: WCAG 1.4.11, not the text
      // bar. The 4.5 figure only ever applied to the app-name label that API
      // 30 and earlier also tinted — see the next test.
      _surfaces.forEach((name, bg) {
        expect(_contrast(kFlashNotificationAccent, bg),
            greaterThanOrEqualTo(3.0),
            reason: '$name is below the graphical-object bar');
      });
    });

    test('and does NOT clear 4.5:1 on either dark surface, by decision', () {
      // §5.1, closed. minSdkVersion is 24, so the API<=30 window where
      // `Notification.color` also tinted the ~12sp app-name label is live.
      // The answer is that those shades get a slightly quiet app name, not
      // that this token moves.
      //
      // Pinned as a shortfall rather than left implicit, so nobody reads the
      // 3:1 test above as "it passes" and nobody nudges the hue to chase 4.5
      // on a surface OEM skins redraw anyway.
      expect(_contrast(kFlashNotificationAccent, _surfaces['dark shade #1B1B1B']!),
          lessThan(4.5));
      expect(_contrast(kFlashNotificationAccent, _surfaces['shade card #1F2223']!),
          lessThan(4.5));
    });

    test('#12787F stays rejected, and here is why in numbers', () {
      // Recorded so the next person to look at 3.69 and reach for a darker
      // teal finds the measurement rather than repeating it. It buys 0.88 on
      // a light shade and gives back 0.66 and 0.63 on the two dark ones,
      // landing at 3.06 — a 0.06 margin against a surface nobody controls.
      const rejected = Color(0xFF12787F);
      expect(_contrast(rejected, _surfaces['light shade #FFFFFF']!),
          greaterThan(_contrast(
              kFlashNotificationAccent, _surfaces['light shade #FFFFFF']!)));
      expect(_contrast(rejected, _surfaces['shade card #1F2223']!),
          lessThan(3.1),
          reason: 'this is the number that disqualified it');
    });
  });

  group('the call sites, read from source', () {
    // Per the standing rule: a test that constructs its own subject proves a
    // fact about the test. These read `lib/` instead, because the plugin
    // cannot be driven in a host run and the question is which values the app
    // passes, not what this file can build.

    final refresh = File('lib/services/refresh_service.dart').readAsStringSync();
    final badge =
        File('lib/services/unread_badge_service.dart').readAsStringSync();

    test('both notifications carry the accent', () {
      expect(refresh, contains('color: kFlashNotificationAccent'));
      expect(badge, contains('color: kFlashNotificationAccent'));
    });

    test('no second copy of the hex anywhere in lib', () {
      // The failure this catches is a literal `Color(0xFF15868E)` appearing
      // beside the constant and then only one of them being updated.
      final strays = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path == 'lib/services/notification_group.dart') continue;
        for (final line in entity.readAsLinesSync()) {
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('0xFF15868E')) strays.add(path);
        }
      }
      expect(strays, isEmpty, reason: 'duplicated accent in: $strays');
    });

    test('B8: the two channels are separate, and the unread one is LOW', () {
      // **Closed, not outstanding.** B8 asks for the unread notification to
      // move to its own IMPORTANCE_LOW channel. It has always been there:
      // `flash_unread_count` at `Importance.low`, `flash_keyword_alerts` at
      // `Importance.defaultImportance`. Verified live on the Lenovo in pass 8
      // (`mImportance=2`, `mOriginalImp=2`). There is nothing to migrate,
      // which matters because a channel's importance cannot be changed in
      // code once it exists.
      expect(badge, contains("kUnreadBadgeChannelId = 'flash_unread_count'"));
      expect(badge, contains('importance: Importance.low'));

      expect(refresh, contains("_kKeywordChannelId = 'flash_keyword_alerts'"));
      expect(refresh, contains('importance: Importance.defaultImportance'));

      // Code lines only. Both files now DISCUSS the other's channel in a
      // comment — the summary's doc explains the lazy-creation hazard by
      // naming exactly this pair — and a whole-file `contains` matched that
      // prose and failed on correct code. Same trap as a grep that counts
      // comments: the check has to look where the behaviour is.
      expect(_code(refresh), isNot(contains('flash_unread_count')),
          reason: 'the keyword path must not post to the unread channel');
      expect(_code(badge), isNot(contains('flash_keyword_alerts')),
          reason: 'and vice versa');
    });

    test('the summary creates its channel before posting into it', () {
      // The ordering hazard from pass 8 recon: channels are created lazily on
      // first post, and a device can hold one Flash channel and not the
      // other. A summary that inherited the channel's existence from a child
      // would depend on a child having fired on that device, ever.
      final create = refresh.indexOf('createNotificationChannel');
      final post = refresh.indexOf('setAsGroupSummary');
      expect(create, greaterThan(-1),
          reason: 'the keyword channel is never created explicitly');
      expect(post, greaterThan(create),
          reason: 'the summary posts before its channel is created');
    });

    test('the summary has its own fixed id, clear of the minted range', () {
      // Per-notification ids stay minted from the sorted keyword set — that
      // is the fix that stops two sets collapsing into each other, and this
      // must not undo it. The summary is the opposite case: one notification
      // that always replaces itself.
      expect(refresh, contains('kAlertSummaryNotificationId = 3'));
      expect(refresh, contains('notificationIdFor(plan.keywords)'),
          reason: 'the per-set minting must survive B7');
    });

    test('and nothing is summarised for a single alert', () {
      expect(refresh, contains('if (count < 2) return;'),
          reason: 'one alert plus a summary saying "1 keyword alert" is two '
              'notifications for one event');
    });
  });
}
