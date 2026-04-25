class KeywordAlert {
  final int? id;
  final String keyword;
  final bool wholeWord;
  final int createdAt;

  const KeywordAlert({
    this.id,
    required this.keyword,
    required this.wholeWord,
    required this.createdAt,
  });

  factory KeywordAlert.fromMap(Map<String, dynamic> map) {
    return KeywordAlert(
      id: map['id'] as int?,
      keyword: map['keyword'] as String,
      wholeWord: (map['whole_word'] as int) == 1,
      createdAt: map['created_at'] as int,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'keyword': keyword,
        'whole_word': wholeWord ? 1 : 0,
        'created_at': createdAt,
      };

  KeywordAlert copyWith({int? id, String? keyword, bool? wholeWord, int? createdAt}) {
    return KeywordAlert(
      id: id ?? this.id,
      keyword: keyword ?? this.keyword,
      wholeWord: wholeWord ?? this.wholeWord,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
