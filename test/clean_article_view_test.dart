import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/models/content_block.dart';
import 'package:flash/widgets/clean_article_view.dart';

/// Network images need no special machinery here. flutter_test installs an
/// HttpClient that fails every request, and flutter_cache_manager's
/// path_provider channel is absent under test — CachedNetworkImage swallows
/// both and renders its errorWidget. Same reliance as
/// article_card_thumbnail_test. Never pumpAndSettle: the cache manager's
/// future is out of band and there is no reason to depend on its timing.
Future<void> _pump(WidgetTester tester, List<ContentBlock> blocks) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: CleanArticleView(blocks: blocks)),
  ));
  await tester.pump();
}

void main() {
  testWidgets('renders one item per block, in source order', (tester) async {
    await _pump(tester, [
      HeadingBlock(1, 'The headline'),
      ParagraphBlock('First paragraph.'),
      ParagraphBlock('Second paragraph.'),
    ]);

    expect(find.byKey(const ValueKey('cleanArticleView')), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('cleanBlock_$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('cleanBlock_3')), findsNothing);

    final first = tester.getTopLeft(find.text('The headline'));
    final second = tester.getTopLeft(find.text('First paragraph.'));
    expect(first.dy, lessThan(second.dy));
  });

  testWidgets('heading levels get distinct, descending sizes', (tester) async {
    await _pump(tester, [
      HeadingBlock(1, 'Level one'),
      HeadingBlock(2, 'Level two'),
      HeadingBlock(3, 'Level three'),
    ]);

    double sizeOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.fontSize!;

    // Pulled from the theme, not hardcoded here — the assertion is the
    // ordering, so it survives a palette or typography change.
    expect(sizeOf('Level one'), greaterThan(sizeOf('Level two')));
    expect(sizeOf('Level two'), greaterThan(sizeOf('Level three')));
  });

  testWidgets('headings are bold', (tester) async {
    await _pump(tester, [HeadingBlock(2, 'A heading')]);
    expect(tester.widget<Text>(find.text('A heading')).style!.fontWeight,
        FontWeight.w700);
  });

  group('lists', () {
    testWidgets('ordered lists are numbered', (tester) async {
      await _pump(tester, [
        ListBlock(ordered: true, items: ['alpha', 'beta', 'gamma']),
      ]);

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('gamma'), findsOneWidget);
    });

    testWidgets('unordered lists are bulleted', (tester) async {
      await _pump(tester, [
        ListBlock(ordered: false, items: ['alpha', 'beta']),
      ]);

      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('1.'), findsNothing);
    });
  });

  testWidgets('quotes are set apart from body text', (tester) async {
    await _pump(tester, [
      ParagraphBlock('Ordinary body text.'),
      QuoteBlock('Something someone said.'),
    ]);

    final quote = tester.widget<Text>(find.text('Something someone said.'));
    final body = tester.widget<Text>(find.text('Ordinary body text.'));

    // Visually distinguished, not merely present.
    expect(quote.style!.fontStyle, FontStyle.italic);
    expect(body.style!.fontStyle, isNot(FontStyle.italic));
    expect(quote.style!.color, isNot(body.style!.color));
  });

  group('images', () {
    testWidgets('render through the shared image cache', (tester) async {
      await _pump(tester, [ImageBlock('https://example.com/lead.jpg')]);

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, 'https://example.com/lead.jpg');
    });

    testWidgets('a caption renders when present', (tester) async {
      await _pump(tester, [
        ImageBlock('https://example.com/lead.jpg', caption: 'Who took it'),
      ]);
      expect(find.text('Who took it'), findsOneWidget);
    });

    testWidgets('no caption widget when absent or empty', (tester) async {
      await _pump(tester, [
        ImageBlock('https://example.com/a.jpg'),
        ImageBlock('https://example.com/b.jpg', caption: ''),
      ]);
      // Two images, no caption Text between them.
      expect(find.byType(CachedNetworkImage), findsNWidgets(2));
      expect(find.byType(Text), findsNothing);
    });
  });

  testWidgets('an empty article renders nothing but the list', (tester) async {
    await _pump(tester, []);
    expect(find.byKey(const ValueKey('cleanArticleView')), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });
}
