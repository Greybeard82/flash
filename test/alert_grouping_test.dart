// Keyword-grouping tests for the Alerts tab.
//
// Written independently of the screen that uses it — pure functions over
// plain [AlertEntry] lists, no widget, no database. Mirrors
// day_grouping_test.dart's own approach to the same kind of problem.
//
// Covered behaviours:
//  1. Empty in, empty out.
//  2. An entry appears once per keyword it matched — deliberate duplication.
//  3. Sections are ordered by their own most recent match, descending.
//  4. A keyword with nothing in the input list gets no section.
//  5. A collapsed section contributes only its header row, no entries.
//  6. newestFirst reorders entries within a section, and does not touch
//     which section comes first.

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/alert_entry.dart';
import 'package:flash/utils/alert_grouping.dart';

AlertEntry _entry(
  String guid, {
  required List<String> keywords,
  required int matchedAt,
}) =>
    AlertEntry(
      feedId: 1,
      guid: guid,
      keywords: keywords,
      title: 'Article $guid',
      url: 'https://example.com/$guid',
      matchedAt: matchedAt,
    );

/// The section list collapsed to flat strings — `List`'s `==` is identity,
/// not element-wise, so comparing nested `List<AlertEntry>`s (or records
/// wrapping them) directly against literals would fail even when the
/// contents genuinely match. Flat strings sidestep that entirely, matching
/// day_grouping_test.dart's own `_shape` helper for the same reason. Order
/// of both the sections and the guids within each is significant.
List<String> _shape(List<(String, List<AlertEntry>)> sections) => [
      for (final (keyword, entries) in sections)
        '$keyword:${entries.map((e) => e.guid).join(',')}',
    ];

void main() {
  group('groupByKeyword', () {
    test('empty in, empty out', () {
      expect(groupByKeyword(const []), isEmpty);
    });

    test('one entry, one keyword: one section with that one entry', () {
      final sections = groupByKeyword([
        _entry('a', keywords: const ['zelda'], matchedAt: 100),
      ]);
      expect(_shape(sections), ['zelda:a']);
    });

    test('an entry matching two keywords appears once under each', () {
      final entry =
          _entry('a', keywords: const ['zelda', 'ps5'], matchedAt: 100);
      final sections = groupByKeyword([entry]);

      expect(sections, hasLength(2),
          reason: 'two keywords hit, so two sections — this is a summing of '
              'keywords, not a partition of the entry list');
      final zelda = sections.firstWhere((s) => s.$1 == 'zelda');
      final ps5 = sections.firstWhere((s) => s.$1 == 'ps5');
      expect(zelda.$2.single, same(entry),
          reason: 'the identical object under both, not a copy — so marking '
              'it read through one section is visible through the other on '
              'the very next rebuild');
      expect(ps5.$2.single, same(entry));
    });

    test('a keyword with nothing in the input gets no section', () {
      // Only "zelda" appears on anything; "ps5" is not mentioned at all.
      final sections = groupByKeyword([
        _entry('a', keywords: const ['zelda'], matchedAt: 100),
      ]);
      expect(sections.map((s) => s.$1), ['zelda']);
    });

    test('sections are ordered by their own most recent match, descending',
        () {
      final sections = groupByKeyword([
        _entry('old-zelda', keywords: const ['zelda'], matchedAt: 100),
        _entry('new-ps5', keywords: const ['ps5'], matchedAt: 300),
        _entry('mid-mario', keywords: const ['mario'], matchedAt: 200),
      ]);
      expect(sections.map((s) => s.$1), ['ps5', 'mario', 'zelda']);
    });

    test(
        'a keyword\'s own entry order follows the input order faithfully, '
        'even when one of its entries also belongs to another keyword', () {
      // Newest-first, as AlertMatchRepository.getEntries() always returns —
      // "b" (a double match) comes before "a" (zelda-only, older).
      final sections = groupByKeyword([
        _entry('b', keywords: const ['ps5', 'zelda'], matchedAt: 200),
        _entry('a', keywords: const ['zelda'], matchedAt: 100),
      ]);
      final zelda = sections.firstWhere((s) => s.$1 == 'zelda');
      expect(zelda.$2.first.guid, 'b',
          reason: 'grouping must preserve input order within a keyword '
              'rather than re-deriving its own — "b" leads globally, so it '
              'leads zelda\'s own list too, even though "a" is the entry '
              'that hits *only* zelda');
    });
  });

  group('alertRows', () {
    test('empty entries produce no rows', () {
      expect(
        alertRows(const [], collapsedKeywords: {}, newestFirst: true),
        isEmpty,
      );
    });

    test('an expanded section is a header followed by its entries', () {
      final rows = alertRows(
        [
          _entry('a', keywords: const ['zelda'], matchedAt: 200),
          _entry('b', keywords: const ['zelda'], matchedAt: 100),
        ],
        collapsedKeywords: {},
        newestFirst: true,
      );

      expect(rows, hasLength(3));
      final header = rows[0] as KeywordHeaderRow;
      expect(header.keyword, 'zelda');
      expect(header.count, 2);
      expect(header.collapsed, isFalse);
      expect((rows[1] as KeywordEntryRow).entry.guid, 'a');
      expect((rows[2] as KeywordEntryRow).entry.guid, 'b');
    });

    test('a collapsed section is only its header — count still reflects '
        'every entry it has, not zero', () {
      final rows = alertRows(
        [
          _entry('a', keywords: const ['zelda'], matchedAt: 200),
          _entry('b', keywords: const ['zelda'], matchedAt: 100),
        ],
        collapsedKeywords: {'zelda'},
        newestFirst: true,
      );

      expect(rows, hasLength(1));
      final header = rows.single as KeywordHeaderRow;
      expect(header.collapsed, isTrue);
      expect(header.count, 2,
          reason: 'collapsing hides the entries, not the fact that there '
              'are two of them');
    });

    test('newestFirst: false reverses entries within a section only', () {
      final rows = alertRows(
        [
          _entry('newer', keywords: const ['zelda'], matchedAt: 200),
          _entry('older', keywords: const ['zelda'], matchedAt: 100),
        ],
        collapsedKeywords: {},
        newestFirst: false,
      );

      expect((rows[1] as KeywordEntryRow).entry.guid, 'older');
      expect((rows[2] as KeywordEntryRow).entry.guid, 'newer');
    });

    test('newestFirst does not reorder which section comes first', () {
      final entries = [
        _entry('a', keywords: const ['zelda'], matchedAt: 100),
        _entry('b', keywords: const ['ps5'], matchedAt: 300),
      ];

      List<String> sectionOrder(bool newestFirst) => [
            for (final row in alertRows(entries,
                collapsedKeywords: {}, newestFirst: newestFirst))
              if (row is KeywordHeaderRow) row.keyword,
          ];

      // ps5's only match (300) is more recent than zelda's (100) either way
      // — the toggle must not change that.
      expect(sectionOrder(true), ['ps5', 'zelda']);
      expect(sectionOrder(false), ['ps5', 'zelda']);
    });

    test('a two-keyword entry contributes a row to each of its sections',
        () {
      final entry =
          _entry('a', keywords: const ['zelda', 'ps5'], matchedAt: 100);
      final rows =
          alertRows([entry], collapsedKeywords: {}, newestFirst: true);

      final entryRows = rows.whereType<KeywordEntryRow>().toList();
      expect(entryRows, hasLength(2));
      expect(entryRows.every((r) => identical(r.entry, entry)), isTrue);
    });
  });
}
