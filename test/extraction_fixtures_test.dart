// Extraction against real publisher HTML, not constructed markup.
//
// `extractFromHtml` exists precisely so this is possible without a network
// call. The fixtures under test/fixtures/extraction/ are the actual pages
// saved on 2026-09-08 — the same bytes the app would have fetched.
//
// The point of the pinned block counts is NOT that a particular number is
// correct. It is that these heuristics are one regex away from deleting a
// whole page: the comment above `_junkClassIdPattern` records that happening
// twice already, once from a bare "ad" matching `class="techradar"`. Pages
// that extract well today have to be pinned BEFORE those patterns are touched
// again, so the next change has to explain itself.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/article_extractor.dart';

/// (fixture, source url, expected block count).
///
/// Counts recorded 2026-09-08 after the dedupe/trailing-trim pass. A diff here
/// is not automatically a failure — but it is a change in what readers see,
/// and it has to be looked at rather than re-baselined reflexively.
const _fixtures = <({String name, String url, int blocks})>[
  (
    name: 'techradar_a',
    url:
        'https://www.techradar.com/gaming/ps3/sick-of-sony-killing-physical-games-relive-the-glory-days-with-a-playstation-3-emulator-that-can-play-discs-through-your-pc',
    blocks: 15,
  ),
  (
    name: 'techradar_b',
    url:
        'https://www.techradar.com/how-to-watch/football/porto-vs-man-city-champions-league-2026-27',
    blocks: 44,
  ),
  (
    name: 'verge_a',
    url:
        'https://www.theverge.com/transportation/991400/tesla-cybercab-virtual-joystick-manual-control',
    blocks: 10,
  ),
  (
    name: 'verge_b',
    url: 'https://www.theverge.com/games/991451/white-house-pulls-racist-tetris-clone',
    blocks: 8,
  ),
  (name: 'bbc_a', url: 'https://www.bbc.co.uk/news/articles/cm27v3743mno', blocks: 29),
  (name: 'bbc_b', url: 'https://www.bbc.co.uk/news/articles/cp30kv53qvdo', blocks: 27),
  (
    name: 'eurogamer_a',
    url: 'https://www.eurogamer.net/legend-of-zelda-occarina-of-time-remake-reaction-visuals',
    blocks: 19,
  ),
  (
    name: 'rps_a',
    url:
        'https://www.rockpapershotgun.com/powerwash-simulator-devs-futurlab-laid-off-staff-and-cancelled-an-unrevealed-project-earlier-this-year-but-certainly-kept-quiet-about-it',
    blocks: 6,
  ),
];

/// Pages whose article body is not in the server-rendered HTML at all, so a
/// plain GET cannot extract them. Pinned as null so that if one ever starts
/// working the change is noticed rather than silently absorbed.
const _knownUnextractable = <({String name, String url})>[
  (
    name: 'ign_a',
    url: 'https://www.ign.com/articles/the-legend-of-zelda-ocarina-of-time-remake-fully-revealed',
  ),
  (
    name: 'ign_b',
    url:
        'https://www.ign.com/articles/nintendo-reveals-lego-link-epona-set-for-the-legend-of-zelda-40th-anniversary',
  ),
];

/// Fixtures are stored gzipped: the raw pages are 6.6MB, which is not a
/// reasonable thing to add to a repo for a test asset. Gzipped they are 1.3MB,
/// and dart:io decodes them with no extra dependency.
List<ContentBlock>? _run(String name, String url) {
  final f = File('test/fixtures/extraction/$name.html.gz');
  expect(f.existsSync(), isTrue, reason: 'missing fixture $name.html.gz');
  final html = utf8.decode(gzip.decode(f.readAsBytesSync()), allowMalformed: true);
  return ArticleExtractor().extractFromHtml(html, url);
}

/// Mirrors the trailing-junk heading rule. Deliberately a second, independent
/// statement of the intent rather than a reference to the private regex: a
/// test that imports the implementation's own pattern would pass no matter
/// what that pattern became.
final _recirc = RegExp(
  r'^(read more|read next|more from|more on|more in|related|you may also|'
  r'recommended|trending|most read|most popular|sign up|subscribe|'
  r'follow us|about the author|get in touch)',
  caseSensitive: false,
);

void main() {
  group('every fixture extracts to clean blocks', () {
    for (final f in _fixtures) {
      group(f.name, () {
        test('produces the pinned block count', () {
          final blocks = _run(f.name, f.url);
          expect(blocks, isNotNull, reason: '${f.name} extracted nothing');
          expect(blocks!.length, f.blocks);
        });

        test('emits no image twice', () {
          final srcs =
              _run(f.name, f.url)!.whereType<ImageBlock>().map((i) => i.src).toList();
          expect(srcs.length, srcs.toSet().length,
              reason: 'duplicate image src in ${f.name}: '
                  '${srcs.where((s) => srcs.where((o) => o == s).length > 1).toSet()}');
        });

        test('does not end on recirculation', () {
          final blocks = _run(f.name, f.url)!;
          final last = blocks.last;

          expect(last, isNot(isA<ListBlock>()),
              reason: '${f.name} ends on a list — a flattened link roll');
          expect(last, isNot(isA<ImageBlock>()),
              reason: '${f.name} ends on an image — usually an author portrait');
          if (last is HeadingBlock) {
            expect(_recirc.hasMatch(last.text.trim()), isFalse,
                reason: '${f.name} ends on the heading "${last.text}"');
          }
        });

        test('still has real prose in it', () {
          // The trailing trim has a guard that returns the untrimmed list
          // rather than leave nothing. This is the assertion that would catch
          // it failing to fire.
          final blocks = _run(f.name, f.url)!;
          final prose =
              blocks.whereType<ParagraphBlock>().map((p) => p.text).join(' ');
          expect(prose.length, greaterThan(400),
              reason: '${f.name} was trimmed down to almost nothing');
        });
      });
    }
  });

  group('pages with no server-rendered body', () {
    for (final f in _knownUnextractable) {
      test('${f.name} still yields nothing', () {
        // Not a defect introduced here — these returned null before the
        // dedupe/trim pass too. IGN ships an empty shell and hydrates the
        // article client-side, the same shape as the Kotaku case documented
        // in extractFromHtml. Recorded so clean mode's "not available"
        // banner is understood as correct behaviour for these, not a bug.
        expect(_run(f.name, f.url), isNull);
      });
    }
  });
}
