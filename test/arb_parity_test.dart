// Every language file carries every key.
//
// A missing key is invisible until someone switches locale and finds an
// English string in the middle of a Spanish screen. This reads the .arb files
// off disk and fails the build instead.
//
// Also catches the subtler failure: a key present but left as the English
// text. Some values are legitimately identical across languages ("Flash",
// "OPML", "Backup" in Italian, "{n} articles" in French), so those are
// allow-listed by key+locale rather than skipped wholesale — an entry there
// is a deliberate statement that the word does not translate.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _locales = ['de', 'es', 'fr', 'it'];

/// key -> locales in which sharing the English value is correct.
const Map<String, List<String>> _sameAsEnglishIsFine = {
  'appTitle': ['de', 'es', 'fr', 'it'],
  'feeds': ['de'],
  'filterBubbleTitle': ['de'],
  'themeSystem': ['de'],
  'articlesCount': ['fr'],
  'backup': ['it'],
};

Map<String, String> _load(String locale) {
  final file = File('lib/l10n/app_$locale.arb');
  // Not expect(): this runs at collection time — from main() and from inside
  // group() callbacks — where there is no active test and expect() throws
  // OutsideTestException before any assertion can be reached.
  if (!file.existsSync()) {
    throw StateError('${file.path} is missing');
  }
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in decoded.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

void main() {
  final en = _load('en');

  test('the template has the keys this pass added', () {
    for (final key in [
      'showRead',
      'showReadSubtitle',
      'dayToday',
      'dayYesterday',
    ]) {
      expect(en.containsKey(key), isTrue, reason: '$key missing from app_en.arb');
    }
  });

  for (final locale in _locales) {
    group(locale, () {
      final translations = _load(locale);

      test('has every key the template has', () {
        final missing = en.keys.where((k) => !translations.containsKey(k));
        expect(missing, isEmpty,
            reason: 'app_$locale.arb is missing: ${missing.join(', ')}');
      });

      test('has no keys the template does not', () {
        final extra = translations.keys.where((k) => !en.containsKey(k));
        expect(extra, isEmpty,
            reason: 'app_$locale.arb has orphans: ${extra.join(', ')}');
      });

      test('no value is left as the English text', () {
        final untranslated = [
          for (final entry in translations.entries)
            if (en[entry.key] == entry.value &&
                entry.value.length > 3 &&
                !(_sameAsEnglishIsFine[entry.key] ?? const []).contains(locale))
              entry.key,
        ];
        expect(untranslated, isEmpty,
            reason: 'app_$locale.arb still shows English for: '
                '${untranslated.join(', ')}. If a word genuinely does not '
                'translate, add it to _sameAsEnglishIsFine.');
      });
    });
  }
}
