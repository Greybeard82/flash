// No new alpha-faked ink, and an explicit record of what was left behind.
//
// Pass 2 replaced 41 `onSurface.withValues(alpha: n)` sites with named roles.
// This is what stops the other kind of regression: not a wrong colour, but a
// *new* faked one appearing in a file nobody was looking at. Alpha over ink is
// the path of least resistance — it is one expression, it needs no import, and
// it looks reasonable — so without a guard the count creeps back up.
//
// The allowlist is the point of the file. Every entry below is a site somebody
// looked at and decided to leave, with the reason attached. That turns "we left
// some" into a reviewed decision rather than an oversight, and it means adding
// a site is a deliberate act: the test fails, and you either convert it or
// write down why not.
//
// **The pattern is deliberately multiline.** The inventory this pass started
// from was built with a single-line grep and undercounted by twelve, because
// Dart's formatter wraps long chains:
//
//     color: theme.colorScheme.onSurface
//         .withValues(alpha: 0.6),
//
// Those twelve were real sites doing real work, including two on the article
// card. A guard with the same blind spot would have been worse than none.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `onSurface` followed by `.withValues(alpha: …)`, however it is wrapped.
final RegExp _alphaInk = RegExp(
  r'onSurface\s*\.withValues\(\s*alpha:\s*([^)]*)\)',
  multiLine: true,
);

/// file -> alpha expression -> how many occurrences are expected.
///
/// Keyed by the alpha expression rather than a line number, so reformatting the
/// file does not break the test and a genuinely new site still does.
const Map<String, Map<String, int>> _allowed = {
  // ── drag handles ─────────────────────────────────────────────────────────
  // 40x4 rounded Containers at the top of a bottom sheet, each sitting under
  // a `// Handle` comment. A grabber is furniture, not text, and none of the
  // three ink levels describes one.
  'lib/screens/article_summary_sheet.dart': {'0.2': 1},
  'lib/widgets/starter_pack_picker.dart': {'0.2': 1},

  // ── empty-state icons ────────────────────────────────────────────────────
  // Large illustrative glyphs, 48-64px, above their own message. No ink role
  // fits an illustration and there is no mock for one yet. The text beneath
  // each of these WAS converted; only the picture is left.
  'lib/screens/bookmarks_screen.dart': {'0.2': 1}, // bookmark_border, 48px
  'lib/widgets/keyword_alerts_panel.dart': {'0.3': 1}, // notifications, 48px

  // Two categories in one file: 0.3 is the 64px rss_feed empty state, 0.2 is
  // the sheet drag handle.
  'lib/screens/feeds_screen.dart': {'0.3': 1, '0.2': 1},

  // Also two, and they collide on the same alpha: one is the 48px empty-state
  // icon, the other a 20dp leading marker repeated beside every matched
  // article — ornament rather than a meaning-carrying icon.
  'lib/widgets/keyword_group_panel.dart': {'0.3': 2},

  // ── disabled states, and a fill ──────────────────────────────────────────
  // 0.08 is the disabled button's circular wash — a fill, not a glyph. The
  // two 0.3s are the disabled halves of enabled/disabled pairs, so they say
  // "inactive", not "quieter". 0.8 is the *enabled* half of the second pair:
  // converting it alone would split one expression between a role and an
  // alpha, which reads worse than leaving both.
  'lib/widgets/radial_menu.dart': {'0.08': 1, '0.3': 2, '0.8': 1},

  'lib/widgets/article_card.dart': {
    // The favicon monogram: a 26px letter on a placeholder tile, standing in
    // for an image rather than reading as text.
    '0.3': 1,

    // ── unresolved ─────────────────────────────────────────────────────────
    // Read state encoded as opacity, on the publisher line and the timestamp.
    // There is no read-variant of either role, and onSurfaceRead is the title
    // colour specifically. Converting these would silently drop the
    // read/unread distinction on those two elements. Needs a design answer.
    'isRead ? 0.33 : 0.6': 1,
    'isRead ? 0.25 : 0.45': 1,
  },
  // The same shape, on a search result's title.
  'lib/screens/search_screen.dart': {'a.isRead ? 0.5 : 1.0': 1},
};

/// Newspaper mode is out of scope for every pass, and its own theme function
/// legitimately blends ink toward paper.
const _exempt = {'lib/theme/app_theme.dart'};

void main() {
  final root = Directory('lib');

  /// file -> alpha expression -> count, for everything currently in lib/.
  Map<String, Map<String, int>> scan() {
    final found = <String, Map<String, int>>{};
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_exempt.contains(path)) continue;
      for (final m in _alphaInk.allMatches(entity.readAsStringSync())) {
        final alpha = m.group(1)!.trim();
        found.putIfAbsent(path, () => {});
        found[path]![alpha] = (found[path]![alpha] ?? 0) + 1;
      }
    }
    return found;
  }

  test('no alpha-faked ink outside the allowlist', () {
    final found = scan();
    final unexpected = <String>[];

    found.forEach((path, alphas) {
      final allowed = _allowed[path];
      alphas.forEach((alpha, count) {
        final permitted = allowed?[alpha] ?? 0;
        if (count > permitted) {
          unexpected.add('$path  alpha: $alpha  '
              '(found $count, allowed $permitted)');
        }
      });
    });

    expect(unexpected, isEmpty,
        reason: 'New onSurface.withValues(alpha:) sites appeared:\n'
            '  ${unexpected.join('\n  ')}\n\n'
            'Use a named ink role instead — theme.colorScheme.onSurfaceVariant '
            'for secondary text and icons, theme.flashColors.onSurfaceMuted '
            'for tertiary. If the site genuinely is not ink (a scrim, a wash, '
            'a disabled state, an illustration), add it to _allowed in this '
            'file with the reason, so the decision is on the record.');
  });

  test('the allowlist has no stale entries', () {
    // The other direction, and the one that rots quietly. A converted site
    // whose allowlist entry stays behind makes the list a record of what used
    // to be true, and quietly widens the guard for whatever is added next.
    final found = scan();
    final stale = <String>[];

    _allowed.forEach((path, alphas) {
      alphas.forEach((alpha, expected) {
        final actual = found[path]?[alpha] ?? 0;
        if (actual < expected) {
          stale.add('$path  alpha: $alpha  '
              '(allowlist says $expected, found $actual)');
        }
      });
    });

    expect(stale, isEmpty,
        reason: 'The allowlist permits sites that no longer exist:\n'
            '  ${stale.join('\n  ')}\n\n'
            'Remove them — an allowlist is only useful while it is exact.');
  });

  test('the guard sees sites that wrap across two lines', () {
    // The bug in the inventory this pass inherited. A single-line grep found
    // 45 sites; the real number was 57, because the formatter wraps long
    // chains. Twelve real sites were invisible, two of them on the article
    // card. This asserts the pattern used above does not repeat that.
    const wrapped = '''
      color: theme.colorScheme.onSurface
          .withValues(alpha: 0.6),
    ''';
    expect(_alphaInk.hasMatch(wrapped), isTrue,
        reason: 'the guard must match a wrapped chain, or it inherits the '
            'blind spot that hid twelve sites');

    const inline = 'color: theme.colorScheme.onSurface.withValues(alpha: 0.6),';
    expect(_alphaInk.hasMatch(inline), isTrue);
  });

  test('the allowlist is small, and every entry carries a reason', () {
    // Not a real assertion so much as a tripwire on drift: if this number
    // climbs, the pass has stopped being a conversion and started being an
    // exception list.
    final total =
        _allowed.values.expand((m) => m.values).fold<int>(0, (a, b) => a + b);
    expect(total, 16,
        reason: 'Pass 2 converted 41 sites and left exactly 16: 3 sheet drag '
            'handles, 4 empty-state icons, 1 repeated row marker, 1 favicon '
            'monogram, 4 in the radial menu (a disabled wash, two disabled '
            'labels, and the enabled half of one of those pairs), and 3 '
            'read-state conditionals with no role to convert to. Changing '
            'this number means changing that decision.');
  });
}
