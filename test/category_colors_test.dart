// The six category hues, pinned by index.
//
// The index is the contract. It is stored on the folder row, so these six
// entries are load-bearing in a way a derived palette never is: change the
// order of this table and every existing install silently recolours, because
// the stored integers now point at different hues.
//
// Which is also why the lookup takes an index and not a name. Starter-pack
// category names are resolved from ARB keys at seeding time and then become
// ordinary user data, so "Tech" on an English device is "Technik" on a German
// one — any name-derived rule gives two installs of the same pack different
// colours. There is a test below that would fail if someone reintroduced one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/category_colors.dart';

void expectColor(Color actual, int argb, String what) {
  expect(actual.toARGB32(), argb,
      reason: '$what should be #${argb.toRadixString(16).toUpperCase()}, '
          'was #${actual.toARGB32().toRadixString(16).toUpperCase()}');
}

/// index -> (name, tick, light bg, light fg, dark bg, dark fg)
const _expected = [
  (0, 'World News', 0xFF93A3BC, 0xFFEEF1F7, 0xFF45556E, 0xFF1B2330, 0xFFA9BEDA),
  (1, 'Tech', 0xFF89B2B4, 0xFFEAF4F4, 0xFF2A6266, 0xFF122624, 0xFF8FC3C4),
  (2, 'Gaming', 0xFFA79AC0, 0xFFF3EFF7, 0xFF5B4A78, 0xFF231E2E, 0xFFB6A7CE),
  (3, 'Travelling', 0xFFBCA97C, 0xFFF6F2E8, 0xFF6B5A32, 0xFF26220F, 0xFFCDBB8E),
  (4, 'Sports', 0xFF9BB79A, 0xFFEDF4EC, 0xFF3C5C3B, 0xFF152317, 0xFFA6C6A5),
  (5, 'Fitness / Health', 0xFFC39BA4, 0xFFF8EFF1, 0xFF73404B, 0xFF2A1A1E,
      0xFFD2A9B2),
];

void main() {
  group('the six hues, by index', () {
    for (final (i, name, tick, lightBg, lightFg, darkBg, darkFg) in _expected) {
      test('$i is $name', () {
        final l = categoryPalette(i, Brightness.light);
        expectColor(l.tick, tick, '$name tick (light)');
        expectColor(l.chipBackground, lightBg, '$name chip bg (light)');
        expectColor(l.chipForeground, lightFg, '$name chip fg (light)');

        final d = categoryPalette(i, Brightness.dark);
        expectColor(d.tick, tick, '$name tick (dark)');
        expectColor(d.chipBackground, darkBg, '$name chip bg (dark)');
        expectColor(d.chipForeground, darkFg, '$name chip fg (dark)');
      });
    }

    test('there are exactly six', () {
      expect(kCategoryHueCount, 6);
    });

    test('the tick is one colour in both themes', () {
      // The chip needs a background and a foreground per brightness; the tick
      // is a single mark on the row and reads the same either way.
      for (var i = 0; i < kCategoryHueCount; i++) {
        expect(categoryPalette(i, Brightness.light).tick,
            categoryPalette(i, Brightness.dark).tick);
      }
    });

    test('no two hues share a tick', () {
      final ticks = {
        for (var i = 0; i < kCategoryHueCount; i++)
          categoryPalette(i, Brightness.light).tick
      };
      expect(ticks, hasLength(kCategoryHueCount));
    });
  });

  group('an out-of-range index wraps rather than throwing', () {
    // The column is an ordinary integer. A future "change category colour"
    // screen, a hand-edited database or a migration bug can put anything in
    // it, and a category in the wrong colour is a far smaller problem than a
    // feed screen that will not build.
    test('past the end', () {
      expect(categoryPalette(6, Brightness.light).tick,
          categoryPalette(0, Brightness.light).tick);
      expect(categoryPalette(13, Brightness.dark).chipBackground,
          categoryPalette(1, Brightness.dark).chipBackground);
    });

    test('negative', () {
      expect(() => categoryPalette(-1, Brightness.light), returnsNormally);
      expect(() => categoryPalette(-7, Brightness.dark), returnsNormally);
    });

    test('absurd', () {
      expect(() => categoryPalette(1 << 30, Brightness.light), returnsNormally);
    });
  });

  group('picking an index for a new category', () {
    test('an empty library starts at 0', () {
      expect(nextCategoryColorIndex(const []), 0);
    });

    test('it takes the lowest free hue, not the next one along', () {
      // So deleting the second of three categories and adding another reuses
      // the gap instead of marching towards the wrap.
      expect(nextCategoryColorIndex(const [0, 2]), 1);
      expect(nextCategoryColorIndex(const [0, 1, 2]), 3);
    });

    test('once all six are taken it spreads rather than throwing', () {
      final all = List.generate(kCategoryHueCount, (i) => i);
      expect(() => nextCategoryColorIndex(all), returnsNormally);
      expect(nextCategoryColorIndex(all), inInclusiveRange(0, 5));
    });

    test('out-of-range stored values still count as taken', () {
      // 6 is hue 0 after wrapping, so 0 is not free.
      expect(nextCategoryColorIndex(const [6]), 1);
    });
  });

  group('the lookup cannot be keyed off a name', () {
    test('categoryPalette takes an int', () {
      // A compile-time guarantee really, but stated so the reasoning above
      // has somewhere to live that a future edit has to read.
      const int index = 3;
      expect(() => categoryPalette(index, Brightness.light), returnsNormally);
    });
  });
}
