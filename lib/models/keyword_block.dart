class KeywordBlock {
  final int? id;
  final String keyword;
  final bool wholeWord;
  final int createdAt;

  const KeywordBlock({
    this.id,
    required this.keyword,
    this.wholeWord = false,
    required this.createdAt,
  });

  factory KeywordBlock.fromMap(Map<String, dynamic> map) {
    return KeywordBlock(
      id: map['id'] as int?,
      keyword: map['keyword'] as String,
      wholeWord: (map['whole_word'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'keyword': keyword,
      'whole_word': wholeWord ? 1 : 0,
      'created_at': createdAt,
    };
  }

  KeywordBlock copyWith({int? id, String? keyword, bool? wholeWord, int? createdAt}) {
    return KeywordBlock(
      id: id ?? this.id,
      keyword: keyword ?? this.keyword,
      wholeWord: wholeWord ?? this.wholeWord,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
