// Every empty state answers to the same two roles, in the same order.
//
// **The rule, and why it is not arbitrary.** When a screen is empty, that copy
// is the only content on it. It is not supporting text, so the most recessive
// role is the wrong one:
//
//   * one piece of copy  → `colorScheme.onSurfaceVariant`
//   * two pieces of copy → `onSurfaceVariant` first, `flashColors
//     .onSurfaceMuted` second
//
// The app was split 2–2 on this. Bookmarks and the Alerts tab used the muted
// role for their only line; the feed's caught-up state and Categories used the
// variant one; the keyword alerts panel used muted for *both* of its two, so
// the pair read as one grey paragraph with an arbitrary break in it.
//
// **This guard reads the source, not a rendered frame, and that is a
// deliberate trade.** Four of these six states need a database on a real
// isolate before they will render a single widget, and the thing being checked
// is which role name is written next to a glyph — a fact about the file. What
// the source cannot prove is that the widget is reached, so the last group
// pins the site list itself.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every file that paints an empty state with the shared glyph-plus-copy
/// shape. Listed rather than discovered so that a new empty state which
/// forgets the glyph shows up as a missing entry here rather than as silence.
const _emptyStates = <String>[
  'lib/screens/feeds_screen.dart',
  'lib/screens/feed_screen.dart',
  'lib/screens/bookmarks_screen.dart',
  'lib/screens/alerts_screen.dart',
  'lib/widgets/keyword_alerts_panel.dart',
  'lib/widgets/keyword_group_panel.dart',
];

/// The tablet's idle reading pane is **not** an empty state, and was swept
/// into this list before `ink_roles_test.dart` said otherwise.
///
/// The rule above rests on the copy being the only content on the screen.
/// Nothing is empty here: the middle column is full of articles and this is
/// the right-hand column waiting to be told which one. It is genuinely
/// secondary to the list beside it, which is why pass 2 gave it
/// `onSurfaceMuted` for both the glyph and the text and pinned it in both
/// brightnesses.
///
/// Listed rather than merely absent so that the exclusion is a decision on the
/// record instead of an oversight that happens to pass.
const String _idlePane = 'lib/widgets/article_detail_pane.dart';

/// `empty_state.dart` is deliberately not in the list above.
///
/// It is the first-run state and a different component: an 80dp **brand mark**
/// rather than a decorative glyph, a `headlineSmall` w700 heading rather than a
/// line of copy, and a filled button under it. Its one line of body copy is
/// already `onSurfaceVariant`, so it obeys the rule; what it does not share is
/// the shape the rule is expressed in. Forcing the rule onto it would demote
/// its heading to a caption.
///
/// Whether the brand mark should be `illustration` like every other glyph is a
/// design question, logged in handoff 9.2 and not answered by a sweep.
const String _brandState = 'lib/widgets/empty_state.dart';

final RegExp _illustration = RegExp(r'flashColors\.illustration');
final RegExp _roleColour =
    RegExp(r'color:\s*(?:[\w.()]*\.)?(?:flashColors|colorScheme)\.(\w+)');

({int line, String role})? _firstColourAfter(List<String> lines, int start) {
  for (var i = start; i < lines.length && i < start + 40; i++) {
    if (lines[i].trimLeft().startsWith('//')) continue;
    final m = _roleColour.firstMatch(lines[i]);
    if (m != null) return (line: i + 1, role: m.group(1)!);
  }
  return null;
}

void main() {
  group('the first copy under an empty-state glyph is onSurfaceVariant', () {
    // Scans forward from each `illustration` glyph to the next colour role.
    // That next role IS the first piece of copy — the glyph carries its own
    // colour on its own line, and nothing else sits between a glyph and the
    // text under it.
    for (final path in _emptyStates) {
      test(path.split('/').last, () {
        final lines = File(path).readAsLinesSync();
        final offenders = <String>[];
        var glyphs = 0;

        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trimLeft().startsWith('//')) continue;
          if (!_illustration.hasMatch(lines[i])) continue;
          glyphs++;

          final next = _firstColourAfter(lines, i + 1);
          if (next == null) {
            offenders.add('$path:${i + 1} glyph with no copy after it');
            continue;
          }
          if (next.role != 'onSurfaceVariant') {
            offenders.add('$path:${next.line} first copy is '
                '${next.role}, not onSurfaceVariant');
          }
        }

        expect(glyphs, greaterThan(0),
            reason: '$path is listed as an empty state and paints no '
                'illustration glyph. Either it lost one — in which case it is '
                'the bare-text state this pass removed from Alerts — or it '
                'should come off the list.');
        expect(offenders, isEmpty,
            reason: 'Empty-state copy takes the first role, not the '
                'recessive one:\n  ${offenders.join('\n  ')}\n\n'
                'onSurfaceMuted is for a SECOND piece of copy under a first.');
      });
    }
  });

  group('the list itself', () {
    test('every listed file exists', () {
      // A path typo empties the scan and turns the whole file into a guard
      // that reports success. It has happened in this repo before.
      for (final path in [..._emptyStates, _brandState, _idlePane]) {
        expect(File(path).existsSync(), isTrue, reason: '$path is not there');
      }
    });

    test('no empty state outside the list paints an illustration glyph', () {
      // The half that would rot quietly: a seventh empty state appears, is
      // never added here, and picks whichever role its author remembered.
      final known = {..._emptyStates, _brandState, _idlePane};
      final strays = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (known.contains(path)) continue;
        if (path == 'lib/theme/app_theme.dart') continue;

        final hit = entity
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .any(_illustration.hasMatch);
        if (hit) strays.add(path);
      }

      expect(strays, isEmpty,
          reason: 'These paint an empty-state glyph and are not covered:\n  '
              '${strays.join('\n  ')}\n\nAdd them to _emptyStates.');
    });

    test('the brand state obeys the rule even though it is exempt from the '
        'shape', () {
      // Stated rather than implied. `empty_state.dart` is excluded because its
      // structure is different, not because its roles are — and if its body
      // copy ever went muted, the exemption would be hiding a real drift.
      final src = File(_brandState).readAsStringSync();
      expect(src, contains('colorScheme.onSurfaceVariant'));
      expect(src, isNot(contains('onSurfaceMuted')),
          reason: 'the first-run state has one line of body copy, so the '
              'second role has nothing to do there');
    });

    test('the idle reading pane is still tertiary, and stays that way', () {
      // The exclusion, asserted rather than implied. If this pane ever moves
      // onto the empty-state roles it should be because somebody decided to,
      // and this test plus `ink_roles_test.dart` are the two places that
      // would have to change together. It was swept in during this pass and
      // reverted when the second of those failed.
      final src = File(_idlePane).readAsStringSync();
      expect(src, contains('flashColors.onSurfaceMuted'));
      expect(src, isNot(contains('flashColors.illustration')),
          reason: 'the idle pane is not an empty state — nothing is empty, '
              'the list beside it is full of articles');
    });

    test('Alerts has a glyph now, and it is the destination\'s own', () {
      // 3.2 specifically. Pinned by name because "some icon" would let a
      // future edit swap the bell for something generic and stay green.
      final src = File('lib/screens/alerts_screen.dart').readAsStringSync();
      expect(src, contains('Icons.notifications_none_rounded'));
      expect(src, contains('flashColors.illustration'));
    });
  });
}
