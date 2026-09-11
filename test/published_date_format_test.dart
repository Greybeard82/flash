// The absolute publish date shown beside the publisher.
//
// Google Play's News and Magazines policy requires a clear publication date on
// every article. The cards' relative stamp ("3h ago") does not satisfy that —
// it says how long ago, never when — so this format exists alongside it rather
// than replacing it.
//
// What is worth pinning is the locale handling. A hardcoded pattern is the
// easy mistake here, and it is invisible in English: it would put the month
// before the day for a German reader and force a 12-hour clock on locales that
// do not use one.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:flash/utils/date_utils.dart';

void main() {
  // In the app, GlobalMaterialLocalizations.delegate loads the date symbols
  // for the active locale. There is no MaterialApp here, so they are loaded
  // by hand — the same symbols, reached a different way.
  setUpAll(initializeDateFormatting);

  test('a null timestamp formats as empty, not as the epoch', () {
    // publishedAt is nullable, and an article with no date must show nothing
    // rather than "Jan 1, 1970".
    expect(formatPublishedDate(null, 'en'), '');
  });

  test('a real timestamp carries the year', () {
    final millis = DateTime(2026, 3, 14, 15, 9).millisecondsSinceEpoch;
    final formatted = formatPublishedDate(millis, 'en');

    expect(formatted, contains('2026'));
    expect(formatted, contains('14'));
    expect(formatted, isNotEmpty);
  });

  test('German formats differently from English', () {
    // The assertion is deliberately "different", not a literal string: intl's
    // exact output is its business and changes between versions. What must
    // hold is that the locale is actually reaching DateFormat — passing a
    // hardcoded pattern would make these two identical.
    final millis = DateTime(2026, 3, 14, 15, 9).millisecondsSinceEpoch;
    final en = formatPublishedDate(millis, 'en');
    final de = formatPublishedDate(millis, 'de');

    expect(de, isNotEmpty);
    expect(de, isNot(en));
  });
}
