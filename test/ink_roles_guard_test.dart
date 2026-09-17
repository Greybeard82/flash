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
/// Empty, and that is the finished state rather than a starting one.
///
/// Pass 2 converted 41 alpha-faked ink sites and left 16 behind, each with a
/// reason written next to it. Design closed the last of them in section 6:
/// sheet grabbers take onSurfaceMuted like the resize grip already did (6.1),
/// a read search result follows the card elementwise (6.3), the keyword row
/// tick is onSurfaceMuted rather than an illustration (6.4), and disabled and
/// inert turned out to be one role — with the faint wash behind a disabled
/// glyph deleted rather than restyled (6.5).
///
/// So `onSurface` at an alpha is now simply not how this app expresses ink,
/// anywhere, and the guard below has no exceptions to police.
///
/// The one thing that still dims by opacity is `_DimTransition`, and it never
/// appears here because it does not touch `onSurface`: it wraps imagery in an
/// Opacity and a greyscale matrix. No ink role describes a photograph, which
/// is exactly why it was left alone.
///
/// If something lands in this map again, that is a decision worth arguing
/// about rather than a line worth adding.
const Map<String, Map<String, int>> _allowed = {};

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
    expect(total, 0,
        reason: 'The allowlist is empty and should stay that way. Every site '
            'it used to hold was closed by Design section 6 — grabbers and '
            'the keyword tick to onSurfaceMuted, the search result to the '
            'card rules, and the radial menu disabled state to the inert '
            'role with its wash removed. Adding an entry here means arguing '
            'that some new thing cannot be expressed as a role, which is a '
            'conversation, not a diff.');
  });

  test('nothing reads FlashColors through a null check', () {
    // The other way to fake ink: not alpha over onSurface, but
    // `theme.extension<FlashColors>()!` — which throws rather than degrades.
    //
    // There is no allowlist here and there should never be one. The bang form
    // has no legitimate use now that `theme.flashColors` exists: it is the
    // same lookup with a crash attached. It already cost this branch once,
    // when pass 1 shipped it into article_card.dart and Newspaper mode —
    // which registers no extensions — died on the feed the moment a user
    // turned it on. The accessor falls back; the bang does not.
    //
    // Comment lines are stripped before matching, because the accessor's own
    // doc comment names the form it replaces, and prose explaining why not to
    // write something must not read as writing it.
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final code = entity
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      if (code.contains('extension<FlashColors>()!')) {
        offenders.add(entity.path.replaceAll(r'\', '/'));
      }
    }

    expect(offenders, isEmpty,
        reason: 'These read the ink roles through a null check:\n'
            '  ${offenders.join('\n  ')}\n\n'
            'Use theme.flashColors instead. It resolves the extension when '
            'the theme carries one and falls back to a blended grey when it '
            'does not, which is what keeps Newspaper mode and every stock '
            'ThemeData in a widget test from throwing.');
  });

  test('the comment-stripping does not hide real code', () {
    // Guarding the guard. If the strip were too eager — dropping any line
    // containing "//" rather than only lines starting with it — a trailing
    // comment would take the code before it out of scope, and the no-allowlist
    // rule above would quietly have a hole in it.
    String strip(String src) =>
        src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

    const prose = '/// Use this rather than `theme.extension<FlashColors>()!`.';
    expect(strip(prose).contains('extension<FlashColors>()!'), isFalse,
        reason: 'a doc comment naming the form must not trip the guard');

    const real = 'final c = theme.extension<FlashColors>()!.onSurfaceMuted;';
    expect(strip(real).contains('extension<FlashColors>()!'), isTrue);

    const trailing =
        'final c = theme.extension<FlashColors>()!.onSurfaceMuted; // why';
    expect(strip(trailing).contains('extension<FlashColors>()!'), isTrue,
        reason: 'code with a trailing comment is still code');
  });

  test('nothing aliases onSurface into a local and thins that', () {
    // The hole the allowlist fell through, found by cross-checking the design
    // document against the code rather than by this file.
    //
    // `_NewspaperMasthead` read:
    //
    //     final ink = theme.colorScheme.onSurface;
    //     ...
    //     Divider(color: ink.withValues(alpha: 0.4))
    //     ...
    //     color: ink.withValues(alpha: 0.55)
    //
    // Two alpha-faked ink sites that the pattern above cannot see, because it
    // looks for `onSurface` immediately followed by `.withValues`, and here
    // the two are separated by a variable and twenty lines. The allowlist was
    // reported empty while they were sitting in the file.
    //
    // This is the same class of blind spot as the wrapped-chain one, and the
    // same lesson: a guard that matches a shape rather than a meaning only
    // catches the shapes someone thought of. So this bans the aliasing itself.
    // Binding `onSurface` to a local is not useful on its own — it is one
    // field access — and the only reason to do it is to reuse the value, which
    // is exactly when a `.withValues` tends to appear next to it.
    final aliases = <String>[];

    final pattern = RegExp(
      r'(?:final|var|const)\s+\w+\s*=\s*[\w.]*\.onSurface\s*;',
      multiLine: true,
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == 'lib/theme/app_theme.dart') continue;

      final code = entity
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      for (final m in pattern.allMatches(code)) {
        aliases.add('$path  ${m.group(0)!.trim()}');
      }
    }

    expect(aliases, isEmpty,
        reason: 'These bind onSurface to a local, which is how an alpha gets '
            'applied to it out of sight of the pattern above:\n'
            '  ${aliases.join('\n  ')}\n\n'
            'Read the role at the point of use instead. If the value really '
            'is needed several times, it is still one field access each time, '
            'and the repetition is what keeps it visible.');
  });
}
