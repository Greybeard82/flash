// Pass 7 was a consistency sweep, not a redesign, and a sweep's findings rot
// differently from a feature's.
//
// Nothing here is new behaviour. Every assertion pins a place where a screen
// had stopped inheriting the theme and now does again, so that the next screen
// written by hand fails rather than joins them.
//
// Two of the three groups are source-level on purpose. "No raw `Colors.black`
// anywhere in lib" is a property of the repository, not of a rendered frame,
// and standing up eight screens — several of which need a database on a real
// isolate — to prove a colour is absent costs more than reading the files.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/screens/settings_screen.dart';
import 'package:flash/theme/app_theme.dart';

/// Every Dart file under lib/, minus the one place literals belong.
Iterable<File> _libFiles() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (path == 'lib/theme/app_theme.dart') continue;
    if (path.startsWith('lib/l10n/')) continue;
    yield entity;
  }
}

/// Source lines with comments stripped, so a rule quoted in a doc comment does
/// not read as a violation of itself. That exact false positive is why the
/// line is here: `article_card.dart` explains a bug by naming the
/// `Colors.white` it no longer uses.
Iterable<({String path, int line, String text})> _codeLines() sync* {
  for (final file in _libFiles()) {
    final path = file.path.replaceAll(r'\', '/');
    var n = 0;
    for (final raw in file.readAsLinesSync()) {
      n++;
      final trimmed = raw.trimLeft();
      if (trimmed.startsWith('//')) continue;
      yield (path: path, line: n, text: raw);
    }
  }
}

void main() {
  group('no raw Material colours outside the theme', () {
    // `Colors.black` at 28% behind the quick-settings panel and at 60% behind
    // the radial menu were the last two, and both are `scrim` now — a role
    // that resolves to exactly the same black today, because neither scheme
    // declares one and both fall through to ColorScheme's default.
    //
    // **Byte-identical is the argument for it, not against it.** The swap
    // costs nothing and buys a place for a theme to disagree later. A
    // Newspaper that wanted a warm grey wash over newsprint currently has
    // nowhere to say so, because the value is spelled out in two widgets.

    test('no Colors.black, white, grey or red anywhere in lib', () {
      final offenders = <String>[];
      final banned = RegExp(r'\bColors\.(black|white|grey|gray|red|blue|green|'
          r'orange|amber|yellow|purple|pink|teal|cyan|indigo|brown)\b');

      for (final line in _codeLines()) {
        if (banned.hasMatch(line.text)) {
          offenders.add('${line.path}:${line.line}  ${line.text.trim()}');
        }
      }

      expect(offenders, isEmpty,
          reason: 'These name a colour instead of a role:\n  '
              '${offenders.join('\n  ')}\n\n'
              'Every colour comes from `colorScheme` or `flashColors`. '
              '`Colors.transparent` is fine and deliberately not in this list '
              '— it is an absence, not a colour.');
    });

    test('and Colors.transparent is still allowed, so this is not a ban on '
        'the import', () {
      // A tripwire on the test above rather than on the code. If someone
      // tightened the pattern to all of `Colors.`, this fails and says why,
      // instead of the transparent sites being rewritten into something worse.
      final transparents = _codeLines()
          .where((l) => l.text.contains('Colors.transparent'))
          .toList();
      expect(transparents, isNotEmpty,
          reason: 'if nothing uses Colors.transparent any more, the exemption '
              'in the test above is guarding nothing and should go');
    });
  });

  group('error is for faults, and a bin is not a fault', () {
    // Handoff 3 moved Categories' header delete icon to `onSurfaceVariant` so
    // that deleting a category would not rank equal to renaming it. The two
    // keyword panels had the same bin in the same shape and kept `error`.
    //
    // The theme's own scope for error is written down: inline validation, the
    // stale-feed glyph, and the radial menu's Delete. Handoff 4's "Delete, in
    // Alerts only, keeps error" is about that radial menu — it is the whole
    // subject of the bullet it sits in — and does not reach an IconButton in
    // a panel.

    test('no delete icon is painted in error', () {
      final offenders = <String>[];
      final lines = _codeLines().toList();

      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].text.contains('Icons.delete')) continue;
        // The colour may sit on the same line or the next one — both shapes
        // exist in this repo, which is exactly how the blocklist panel's bin
        // stayed invisible to an eyeball check for four passes.
        final window = [
          lines[i].text,
          if (i + 1 < lines.length) lines[i + 1].text,
          if (i + 2 < lines.length) lines[i + 2].text,
        ].join(' ');

        if (window.contains('colorScheme.error') ||
            window.contains('scheme.error')) {
          // The radial menu is the one blessed site.
          if (lines[i].path.endsWith('radial_menu.dart')) continue;
          offenders.add('${lines[i].path}:${lines[i].line}');
        }
      }

      expect(offenders, isEmpty,
          reason: 'A bin that opens a confirmation is asking a question, not '
              'reporting a fault:\n  ${offenders.join('\n  ')}');
    });

    test('the radial menu really is the exception this exempts', () {
      // The failure mode of an allowlist: if the exempt site stops existing,
      // the exemption silently widens to nothing and nobody notices it was
      // load-bearing.
      final radial = File('lib/widgets/radial_menu.dart').readAsStringSync();
      expect(radial, contains('Icons.delete'),
          reason: 'the exemption above names this file; if its delete is gone, '
              'delete the exemption with it');
    });

    test('no confirmation is filled with an error tint', () {
      // The other half of the same rule, and the one that had drifted into an
      // alpha: the inline "this destroys N cards" prompt was
      // `errorContainer` at 35%. Alpha over a role is not a colour anybody
      // authored, and error on a question reads as though something had
      // already gone wrong.
      final offenders = <String>[];
      for (final line in _codeLines()) {
        if (line.text.contains('errorContainer') &&
            line.text.contains('withValues')) {
          offenders.add('${line.path}:${line.line}  ${line.text.trim()}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'An error tint behind a confirmation:\n  '
              '${offenders.join('\n  ')}');
    });
  });

  group('the ad-privacy row', () {
    // Serving ads in the EEA and UK needs a certified CMP, and consent that
    // can be given has to be withdrawable — which means a permanent entry
    // point rather than a first-launch dialog. The row ships tonight with
    // nothing behind it because Settings is being touched tonight and will
    // not be touched again before the ads pass.

    Future<void> pump(WidgetTester tester, ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        theme: theme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: ListView(children: [
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text(kAdPrivacyRowLabelEn),
              subtitle: Text(
                kAdPrivacyRowSubtitleEn,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.flashColors.onSurfaceMuted),
              ),
              enabled: false,
              onTap: () {},
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
    }

    test('its copy is a constant, not an ARB key', () {
      // Deliberate, and the reason is cost: the real wording ships with the
      // ads pass, and putting a placeholder through de/es/fr/it now means
      // paying for the same row twice — with `arb_parity_test.dart` then
      // holding four translations of a sentence nobody has agreed to.
      expect(kAdPrivacyRowLabelEn, isNotEmpty);
      expect(kAdPrivacyRowSubtitleEn, isNotEmpty);

      final arb = File('lib/l10n/app_en.arb').readAsStringSync();
      expect(arb, isNot(contains(kAdPrivacyRowLabelEn)),
          reason: 'if this string is in the ARB now, the constants should go '
              'and this test with them');
    });

    test('it sits in the source directly after the privacy policy', () {
      // Position is the whole of what shipped tonight, so position is what is
      // pinned. Asserted on the source rather than by driving Settings, which
      // builds four repositories and needs a database on a real isolate
      // before it renders a row.
      final src = File('lib/screens/settings_screen.dart').readAsStringSync();
      final policy = src.indexOf('l10n.privacyPolicy');
      final adRow = src.indexOf('kAdPrivacyRowLabelEn', policy);
      final tail = src.indexOf('SizedBox(height: 24)', policy);

      expect(policy, greaterThan(-1));
      expect(adRow, greaterThan(policy),
          reason: 'the row modifies the policy above it: the policy says what '
              'is collected, this changes what the reader agreed to');
      expect(adRow, lessThan(tail),
          reason: 'and it is the last thing in About, so nothing legal sits '
              'below it');
    });

    test('its handler is a no-op with a reason attached', () {
      // An empty method is indistinguishable from an unfinished one. The rule
      // is that it carries its own explanation, so the next reader does not
      // have to decide whether it was meant to do something.
      final src = File('lib/screens/settings_screen.dart').readAsStringSync();
      expect(src, contains('void _onAdPrivacy()'));
      expect(src, contains('documented no-op'),
          reason: 'the handler must say it is deliberately empty');
      expect(src, isNot(contains('UserMessagingPlatform')),
          reason: 'no UMP SDK in this pass');
      expect(src, isNot(contains('ConsentInformation')),
          reason: 'no consent plumbing in this pass either');
    });

    for (final (name, theme) in [
      ('light', flashQuietInkTheme(brightness: Brightness.light)),
      ('dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
    ]) {
      testWidgets('$name: it renders inert, and its subtitle is muted ink',
          (tester) async {
        await pump(tester, theme);
        expect(tester.takeException(), isNull);

        final subtitle =
            tester.widget<Text>(find.text(kAdPrivacyRowSubtitleEn));
        expect(subtitle.style!.color, theme.flashColors.onSurfaceMuted,
            reason: '$name: the subtitle is secondary copy under a row title');

        // Unpressable is the point: the row is visible so its position can be
        // reviewed, and dead so nobody reaches a consent form that does not
        // exist.
        final tile = tester.widget<ListTile>(find.byType(ListTile));
        expect(tile.enabled, isFalse);
      });
    }
  });
}
