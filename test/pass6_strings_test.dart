// Pass 6: the three new keys, the four changed values, and the two guards the
// brief asked to be made enforceable.
//
// `arb_parity_test.dart` already proves every locale carries every key. This
// file is about the things parity cannot see: that a key resolves to something
// a person could read, that an ICU plural survives the counts it will actually
// be handed, and that two decisions already taken do not quietly come undone.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';

const _locales = ['en', 'de', 'es', 'fr', 'it'];

Map<String, dynamic> _raw(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Future<AppLocalizations> _load(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

void main() {
  group('the three keys this pass added resolve everywhere', () {
    // Deliberately not asserting they differ from English: "Sponsored" and
    // "Sponsorisé" differ, but a locale that legitimately shared a word would
    // fail a test that demanded difference, and `arb_parity_test` already owns
    // the untranslated-value check with its own allowlist.
    //
    // **This group reads the generated accessors, not the .arb files, and the
    // distinction is load-bearing.** Deleting a key from one locale's .arb
    // without regenerating leaves the accessor in place, so this group passes
    // — verified, by doing exactly that to `adSponsored` in Italian. The .arb
    // layer belongs to `arb_parity_test`, which failed on the same mutation
    // naming the file and the key. Neither file covers the other.
    for (final locale in _locales) {
      test(locale, () async {
        final l10n = await _load(locale);

        expect(l10n.bookmarkRemoved.trim(), isNotEmpty);
        expect(l10n.adSponsored.trim(), isNotEmpty);
        expect(l10n.alertNotificationSummary(2).trim(), isNotEmpty);

        // A placeholder left unsubstituted is the failure that looks like a
        // success: the string is non-empty and reads as a bug on a device.
        expect(l10n.alertNotificationSummary(2), contains('2'));
        expect(l10n.alertNotificationSummary(2), isNot(contains('{count}')));
      });
    }
  });

  group('alertNotificationSummary survives every count', () {
    // **The `one` branch is unreachable today, and is written correctly
    // anyway.** There is no group summary notification in the app: `groupKey`
    // is set on the children (`refresh_service.dart`, `unread_badge_service
    // .dart`) but nothing calls `setAsGroupSummary`, so this key has no call
    // site at all. When one is built, how Android treats a group with a single
    // child is version-dependent, and "the platform will never ask for one" is
    // not a thing worth betting a wrong string on.
    //
    // French is the reason this group exists. CLDR puts **0 and 1 both in
    // `one`** for French, so a `one` branch reading "1 alerte" renders "1"
    // when the count is zero. The fix is `{count}` rather than a literal 1,
    // which is already the house style in `alertNotificationCount` and
    // `deleteAlertKeywordBody` — and is not in `unreadCountNotification`,
    // which still hardcodes it.
    for (final locale in _locales) {
      test(locale, () async {
        final l10n = await _load(locale);
        for (final count in [0, 1, 2, 5]) {
          final rendered = l10n.alertNotificationSummary(count);
          expect(rendered.trim(), isNotEmpty,
              reason: '$locale rendered nothing at count $count');
          expect(rendered, isNot(contains('{')),
              reason: '$locale left ICU syntax in the output at $count: '
                  '$rendered');
        }
      });
    }

    test('French says 0, not 1, when the count is zero', () async {
      final l10n = await _load('fr');
      expect(l10n.alertNotificationSummary(0), startsWith('0'),
          reason: 'French routes 0 through the `one` branch. A branch with a '
              'literal "1" in it reports one alert when there are none.');
      expect(l10n.alertNotificationSummary(0), contains('alerte '),
          reason: 'and 0 takes the singular noun in French, which is why the '
              'branch is right even though the number is not 1');
    });

    test('English still says 1, since English 0 is plural', () async {
      final l10n = await _load('en');
      expect(l10n.alertNotificationSummary(0), '0 keyword alerts');
      expect(l10n.alertNotificationSummary(1), '1 keyword alert');
    });
  });

  group('noBookmarks keeps its two lines', () {
    // The string is two sentences split by a literal \n, and the split is the
    // layout: the first line states the state, the second says what to do. A
    // translation that dropped the break would centre one long wrapped
    // paragraph in the empty state instead.
    for (final locale in _locales) {
      test(locale, () async {
        final text = (await _load(locale)).noBookmarks;
        final lines = text.split('\n');
        expect(lines, hasLength(2),
            reason: '$locale: noBookmarks must be exactly two lines, got '
                '${lines.length}');
        for (final line in lines) {
          expect(line.trim(), isNotEmpty);
          // Not a design measurement — a tripwire. The longest line in any
          // locale is French at 50 characters; anything approaching double
          // that has stopped being a two-line empty state.
          expect(line.length, lessThan(90),
              reason: '$locale line is ${line.length} chars: $line');
        }
      });
    }

    test('and nobody is still telling the reader to long-press', () async {
      // The whole point of the change: the action rail put saving one tap
      // away, so the instruction naming a long-press was describing a gesture
      // that still works but is no longer the way in.
      const gone = ['Long-press', 'lang drücken', 'Mantén pulsado',
        'longuement', 'Tieni premuto'];
      for (final locale in _locales) {
        final text = (await _load(locale)).noBookmarks;
        for (final phrase in gone) {
          expect(text, isNot(contains(phrase)),
              reason: '$locale still says "$phrase"');
        }
      }
    });
  });

  test('markAllRead and markAllReadConfirm are separate keys, identical text',
      () async {
    // Handoff 2.2: **keep both keys.** Different widgets read them — the FAB
    // cluster takes one, the confirm sheet's button takes the other — and on
    // the tablet both are on screen at once in the sections column, which is
    // what made the one-word difference visible enough to fix.
    //
    // Deduplicating them would couple a dialog's confirm button to a tooltip
    // key, so the invariant is "same text, two keys" rather than "one key".
    for (final locale in _locales) {
      final l10n = await _load(locale);
      expect(l10n.markAllRead, l10n.markAllReadConfirm,
          reason: '$locale has drifted: "${l10n.markAllRead}" vs '
              '"${l10n.markAllReadConfirm}". Both are correct on their own; '
              'they must not differ from each other.');
    }

    final en = _raw('en');
    expect(en.containsKey('markAllRead'), isTrue);
    expect(en.containsKey('markAllReadConfirm'), isTrue,
        reason: 'the second key is the point — do not collapse them');
  });

  test('alertsFilterAll stays deleted', () {
    // **This replaces the test the brief asked for, and the reason is worth
    // reading before changing it back.**
    //
    // Section 4 asked for a test asserting `allTab` and `alertsFilterAll` are
    // equal in every locale, from handoff 2.4 ("keep both keys, but they must
    // not drift"). That instruction has already been overtaken: handoff 7.7
    // found `alertsFilterAll` had no call site in `lib/` — the Alerts screen
    // never grew the second chip bar it was written for — and ruling 5 of the
    // seven rulings deleted it from all five locales in `dd2d214`.
    //
    // So there is nothing to compare it to. What is worth guarding is the
    // deletion itself: a key removed for having no call site is exactly the
    // kind of thing that gets re-added by someone reading 2.4 and taking it at
    // face value. If the second chip bar is ever built, delete this test in
    // the same commit that adds the call site.
    for (final locale in _locales) {
      expect(_raw(locale).containsKey('alertsFilterAll'), isFalse,
          reason: 'app_$locale.arb has alertsFilterAll back. It was deleted '
              'for having no call site; if it has one now, this test goes '
              'with the commit that gave it one.');
    }

    final lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll(r'\', '/').contains('lib/l10n/'));
    for (final file in lib) {
      expect(file.readAsStringSync(), isNot(contains('alertsFilterAll')),
          reason: '${file.path} references a key that does not exist');
    }
  });

  test('allTab is still there, and still the one chip bar', () {
    // The other half of 2.4, and the half that survived: `allTab` is real, it
    // has a call site, and deleting it would take the folder tab bar's first
    // chip with it.
    for (final locale in _locales) {
      expect(_raw(locale).containsKey('allTab'), isTrue);
    }
    expect(File('lib/widgets/folder_tab_bar.dart').readAsStringSync(),
        contains('l10n.allTab'));
  });
}
