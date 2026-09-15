// B9 and §1.5, for the 1x1 unread widget.
//
// **Say plainly what these prove.** The widget is `RemoteViews` drawn by the
// launcher in another process; a Dart host suite cannot render it, cannot
// resolve `values-night/` against a uiMode, and cannot measure a TextView's
// autosized result. So every assertion here is about the RESOURCES — what the
// XML declares and what the provider computes — and none is about what the
// tile looks like.
//
// What is real:
//   * the four colour values, exactly, in both directories
//   * that the autosize attributes exist with the right bounds
//   * that the clamp threshold is 999 and produces "999+"
//   * that nothing hardcodes a colour where a resource should be
//
// What waits for a device:
//   * whether "999+" actually fits in 64dp, and at what size it settles
//   * whether the tile reads correctly beside the app on a real home screen
//   * whether `values-night/` resolves the way B10 describes
//
// Those three are on the morning list. Nothing here should be read as covering
// them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _day = 'android/app/src/main/res/values/colors.xml';
const _night = 'android/app/src/main/res/values-night/colors.xml';
const _layout = 'android/app/src/main/res/layout/widget_unread.xml';
const _background =
    'android/app/src/main/res/drawable/widget_unread_background.xml';
const _provider =
    'android/app/src/main/kotlin/io/getflash/app/UnreadWidgetProvider.kt';

String _read(String path) => File(path).readAsStringSync();

/// The value of a `<color name="...">` entry.
String _colour(String xml, String name) {
  final match =
      RegExp('<color name="$name">([^<]+)</color>').firstMatch(xml);
  expect(match, isNotNull, reason: 'no colour named $name');
  return match!.group(1)!.trim();
}

/// Kotlin/XML with comments removed, so prose about a value is never mistaken
/// for the value. The same trap the six-term grep has.
///
/// **Stripped as blocks, not as lines, and that distinction cost a failing
/// test.** A line-prefix filter drops the opening `<!--` and leaves every
/// continuation line standing — so the comment above these very colours, which
/// names the palette-era hexes it replaced, survived the filter and matched the
/// assertion that those hexes are gone. Exactly the kind of check that looks
/// right and is structurally blind.
String _code(String source) {
  final withoutBlocks = source
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
  return const LineSplitter()
      .convert(withoutBlocks)
      .where((l) => !l.trimLeft().startsWith('//'))
      .join(' ');
}

void main() {
  group('1.5: four colours, all existing Quiet Ink tokens', () {
    // No new value is introduced. Each of these is already in
    // lib/theme/app_theme.dart, which is the whole point — the tile was
    // newsprint cream under a warm orange, left over from the palette era,
    // sitting on a home screen next to a teal app.
    test('day is surface under onSurface', () {
      final xml = _read(_day);
      expect(_colour(xml, 'widget_unread_bg'), '#FFFFFF',
          reason: 'Quiet Ink light `surface`');
      expect(_colour(xml, 'widget_unread_text'), '#0F1413',
          reason: 'Quiet Ink light `onSurface`');
    });

    test('night is surfaceContainer under onSurface', () {
      final xml = _read(_night);
      expect(_colour(xml, 'widget_unread_bg'), '#161D1C',
          reason: 'Quiet Ink dark `surfaceContainer` — one step up from the '
              'app surface, because the tile sits on a wallpaper');
      expect(_colour(xml, 'widget_unread_text'), '#E7EBEA',
          reason: 'Quiet Ink dark `onSurface`');
    });

    test('none of the four old palette-era values survives', () {
      // Named rather than implied, so a revert is a failure rather than a
      // silent return to newsprint.
      final both = _read(_day) + _read(_night);
      for (final old in ['#F2F1EE', '#E07A1F', '#1D1D1B', '#F2E9DC']) {
        expect(_code(both), isNot(contains(old)),
            reason: '$old is a palette-era widget colour and is back');
      }
    });

    test('the radius is untouched at 16dp', () {
      expect(_read(_background), contains('android:radius="16dp"'));
    });

    test('the layout still reads the resources rather than a literal', () {
      // The failure this catches: someone "simplifies" the -night pair away
      // by hardcoding a colour in the layout, and the tile stops following
      // the OS theme entirely.
      final xml = _read(_layout);
      expect(xml, contains('@color/widget_unread_text'));
      expect(xml, contains('@drawable/widget_unread_background'));
      expect(RegExp(r'android:textColor="#').hasMatch(xml), isFalse);
    });
  });

  group('B9: the clamp and the autosize, which only work together', () {
    test('the threshold is 999, not the badge cap of 99', () {
      // 99 was borrowed from `kMaxBadgeCount`, which caps a small circle the
      // OS draws over an icon. This is a TextView in a 1x1 cell and three
      // digits fit.
      expect(_code(_read(_provider)), contains('MAX_SHOWN = 999'));
    });

    test('and it renders as "<n>+" rather than a bare number', () {
      final code = _code(_read(_provider));
      expect(code, contains(r'"$MAX_SHOWN+"'),
          reason: 'the plus is the whole point of clamping in a TextView we '
              'draw ourselves rather than handing an int to the launcher');
      expect(code, contains('count > MAX_SHOWN'));
    });

    test('autosize is declared, 18sp to 28sp', () {
      // **Without this the clamp alone ellipsises.** "999+" at a fixed 28sp
      // overflows 64dp of usable width, and a TextView that cannot fit its
      // text truncates it — so the widget would say "99" while meaning
      // "999+", which is worse than either.
      final xml = _read(_layout);
      expect(xml, contains('android:autoSizeTextType="uniform"'));
      expect(xml, contains('android:autoSizeMinTextSize="18sp"'));
      expect(xml, contains('android:autoSizeMaxTextSize="28sp"'));
    });

    test('28sp survives as the maximum, which is not a contradiction of 1.5',
        () {
      // 1.5 says the count stays 28sp bold and no layout edit is needed **for
      // the colour change**. Autosize makes 28 a ceiling rather than a fixed
      // value, so one to three digits still render at exactly 28sp. Asserted
      // together so the two lines cannot later read as contradicting.
      final xml = _read(_layout);
      expect(xml, contains('android:textSize="28sp"'));
      expect(xml, contains('android:textStyle="bold"'));
    });

    test('the zero state is untouched', () {
      // It is the widget-picker preview and the pre-first-update value, so it
      // is a real default rather than placeholder text waiting to be removed.
      expect(_read(_layout), contains('android:text="0"'));
    });
  });

  group('what this file does NOT prove', () {
    // Stated as a test so the boundary is in the suite rather than only in a
    // comment at the top. If someone later adds a rendering assertion here it
    // will sit next to this and have to argue with it.
    test('no assertion here renders a RemoteView', () {
      final self = _read('test/widget_resources_test.dart');
      // Anchored to the start of a line, because an unanchored search finds
      // the string inside this test's own reason and fails on a correct file.
      // It did.
      expect(RegExp(r'^\s*testWidgets\(', multiLine: true).hasMatch(self),
          isFalse,
          reason: 'a widget test here would be testing a Flutter tree, which '
              'is not what the launcher draws. The tile is verified on a '
              'device and the morning list says so.');
    });
  });
}
