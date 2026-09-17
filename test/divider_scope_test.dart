// Article lists get a full-bleed hairline. Panels keep their inset one.
//
// The distinction is not decoration. A full-bleed rule says "these are rows of
// one continuous thing"; an inset one says "these are items inside a
// container". An article list is the first; a keyword panel is the second.
//
// **This started as a no-op instruction and turned out to be the opposite.**
// The handoff asked for "Bookmarks' separator becomes the feed's full-bleed
// hairline", and both were already identical — `indent: 16, endIndent: 16` —
// so nothing needed doing. But the spec for the feed's hairline, set two
// batches earlier, was full-bleed with no indent. Bookmarks was matching a
// feed that had itself drifted. Five dividers moved, not one.
//
// Colour and thickness are not asserted here because no site sets them: they
// come from `dividerTheme`, which gives `outlineVariant` at 1dp in Quiet Ink
// and `_npHairline` in Newspaper. That is also why Newspaper survived — its
// divider theme hardcodes the hairline rather than reading `outlineVariant`,
// which until recently resolved to pure black there.
//
// Source-level on purpose. Every one of these lives inside a screen that needs
// a database on a real isolate before it renders a row, and an indent is a
// constructor argument rather than a rendered property — reading the source is
// both cheaper and more direct than standing up four screens to measure a
// gap.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files whose dividers separate article rows. These must be full-bleed.
const _articleLists = <String>[
  'lib/screens/feed_screen.dart',
  'lib/screens/bookmarks_screen.dart',
  'lib/screens/search_screen.dart',
  'lib/screens/alerts_screen.dart',
];

/// Files whose dividers separate items inside a panel. These stay inset, and
/// are listed rather than merely excluded so the decision is on the record.
const _panels = <String>[
  'lib/widgets/keyword_alerts_panel.dart',
  'lib/widgets/keyword_group_panel.dart',
];

final RegExp _indented = RegExp(r'Divider\([^)]*indent:');

Iterable<String> _dividerLines(String path) sync* {
  for (final line in File(path).readAsLinesSync()) {
    if (line.trimLeft().startsWith('//')) continue;
    if (line.contains('Divider(')) yield line.trim();
  }
}

void main() {
  group('article lists are full-bleed', () {
    for (final path in _articleLists) {
      test(path.split('/').last, () {
        final offenders =
            _dividerLines(path).where(_indented.hasMatch).toList();

        expect(offenders, isEmpty,
            reason: 'These separate article rows and must run edge to edge:\n'
                '  ${offenders.join('\n  ')}\n\n'
                'An indented rule reads as "items in a container", which a '
                'feed is not.');
      });
    }
  });

  group('panels keep their inset rule', () {
    for (final path in _panels) {
      test(path.split('/').last, () {
        // The other direction, and the one that would rot quietly: a sweep
        // that made every divider full-bleed would pass the group above and
        // be wrong here.
        final dividers = _dividerLines(path).toList();
        expect(dividers, isNotEmpty,
            reason: 'if this file has no dividers left, this test is guarding '
                'nothing and should be removed');
        expect(dividers.every(_indented.hasMatch), isTrue,
            reason: 'A panel divider separates items inside a container. '
                'Found one running edge to edge in:\n  '
                '${dividers.where((d) => !_indented.hasMatch(d)).join('\n  ')}');
      });
    }
  });

  test('the two sets do not overlap', () {
    // Cheap, but it is the failure mode of a list-driven test: a file in both
    // lists would make one of the groups assert the opposite of the other and
    // the pair would be unfalsifiable.
    expect(_articleLists.toSet().intersection(_panels.toSet()), isEmpty);
  });

  test('every listed file exists', () {
    // A path typo silently empties the scan and turns a guard into a
    // no-op that reports success.
    for (final path in [..._articleLists, ..._panels]) {
      expect(File(path).existsSync(), isTrue, reason: '$path is not there');
    }
  });
}
