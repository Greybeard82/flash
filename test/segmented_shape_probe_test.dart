// §1.7's segmented buttons: verified against a render, not against the theme.
//
// **The reported symptom did not reproduce.** David said they still look like
// capsules. On 0.9.5+30 they do not: a device screenshot of both controls —
// Quick Settings' theme picker and the filter bubble's sort order — shows a
// rounded rectangle at radius ~9 with square interior dividers, which is
// exactly what §1.7 specifies. The theme entry works.
//
// **What the investigation did turn up** is worth keeping, because it is the
// opposite of the expected cause and it will mislead the next person:
//
//   * No call site overrides the theme. All three pass no `style` and no
//     `shape`. The "third bypassed theme value" hypothesis — after
//     `showSelectedIcon` and the `secondary` trap — was wrong this time.
//   * `SegmentedButton` **cannot** take a per-segment shape from a theme.
//     `segmentStyleFor` in segmented_button.dart hardcodes
//     `shape: WidgetStatePropertyAll(RoundedRectangleBorder())` and drops
//     `style?.shape` on the floor. A probe confirmed it: every segment
//     Material renders at `BorderRadius.zero`.
//   * The group's OUTER shape is a different path — `resolve()` reads the raw
//     theme style, `widget ?? theme ?? default` — which is why radius 9 does
//     reach the enclosing clip and the control is not a stadium.
//
// So segments are square by construction and the outer corner is the theme's.
// Anyone reading only the theme, or only the segment render, will conclude the
// opposite of the truth. Hence this file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';

String _code(String path) {
  final raw = File(path).readAsStringSync();
  return const LineSplitter()
      .convert(raw.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' '))
      .where((l) =>
          !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
      .join('\n');
}

void main() {
  group('no call site overrides the theme', () {
    // The regression guard that matters: the theme only reaches these because
    // nothing local shadows it.
    const sites = <String, int>{
      'lib/widgets/filter_bubble.dart': 1,
      'lib/widgets/quick_settings_bubble.dart': 2,
    };

    sites.forEach((path, expected) {
      test('$path has $expected and passes no style or shape', () {
        final code = _code(path);
        expect(RegExp(r'SegmentedButton<').allMatches(code), hasLength(expected),
            reason: 'a new call site needs checking too');

        // Scan each call from its opening line to onSelectionChanged, which
        // is the last argument at every site. Bounding the block by paren
        // indentation over-ran into a neighbouring Text(style:) and failed on
        // correct code -- the same false-positive shape rule 10.4 is about.
        final lines = const LineSplitter().convert(code);
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('SegmentedButton<')) continue;
          for (var j = i; j < lines.length; j++) {
            expect(lines[j], isNot(contains('style:')),
                reason: 'a local style is how a theme silently stops applying');
            expect(lines[j], isNot(contains('shape:')));
            if (lines[j].contains('onSelectionChanged:')) break;
          }
        }
      });
    });
  });

  test('the theme asks for radius 9, which is what the group renders', () {
    // Kept as a value assertion because it is the number §1.7 specifies. The
    // *render* was verified by device screenshot rather than here: what
    // SegmentedButton does to that number internally is the SDK's business
    // and changed shape between the theme and the paint.
    for (final theme in [
      flashQuietInkTheme(brightness: Brightness.light),
      flashQuietInkTheme(brightness: Brightness.dark),
      flashNewspaperTheme(),
    ]) {
      final style = theme.segmentedButtonTheme.style;
      expect(style, isNotNull);
      final shape = style!.shape?.resolve(<WidgetState>{});
      expect(shape, isA<RoundedRectangleBorder>(),
          reason: 'a StadiumBorder here is the capsule coming back');
      final border = shape! as RoundedRectangleBorder;
      expect((border.borderRadius as BorderRadius).topLeft.x, 9);
    }
  });

  testWidgets('segments render square, and that is the SDK not us',
      (tester) async {
    // Asserted so nobody spends an afternoon trying to round the interior
    // dividers from a theme. segmentStyleFor hardcodes it.
    await tester.pumpWidget(MaterialApp(
      theme: flashQuietInkTheme(brightness: Brightness.light),
      home: Scaffold(
        body: Center(
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'a', label: Text('One')),
              ButtonSegment(value: 'b', label: Text('Two')),
            ],
            selected: const {'a'},
            showSelectedIcon: false,
            onSelectionChanged: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final shapes = tester
        .widgetList<Material>(find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.byType(Material),
        ))
        .map((m) => m.shape)
        .whereType<RoundedRectangleBorder>();

    expect(shapes, isNotEmpty);
    for (final s in shapes) {
      expect(s.borderRadius, BorderRadius.zero,
          reason: 'if this ever stops being zero the SDK changed and §1.7 can '
              'be revisited');
    }
  });
}
