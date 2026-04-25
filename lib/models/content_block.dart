sealed class ContentBlock {}

class HeadingBlock extends ContentBlock {
  final int level;
  final String text;
  HeadingBlock(this.level, this.text);
}

class ParagraphBlock extends ContentBlock {
  final String text;
  ParagraphBlock(this.text);
}

class QuoteBlock extends ContentBlock {
  final String text;
  QuoteBlock(this.text);
}

class ListBlock extends ContentBlock {
  final bool ordered;
  final List<String> items;
  ListBlock({required this.ordered, required this.items});
}

class ImageBlock extends ContentBlock {
  final String src;
  final String? caption;
  ImageBlock(this.src, {this.caption});
}
