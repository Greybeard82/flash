class Folder {
  final int? id;
  final String name;
  final int position;
  final int createdAt;

  /// Which of the six category hues this category uses.
  ///
  /// Stored, never derived — see lib/theme/category_colors.dart. Defaults to 0
  /// so older call sites that predate the column still compile; every real
  /// creation path picks a value deliberately.
  final int colorIndex;

  const Folder({
    this.id,
    required this.name,
    required this.position,
    required this.createdAt,
    this.colorIndex = 0,
  });

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as int?,
      name: map['name'] as String,
      position: map['position'] as int,
      createdAt: map['created_at'] as int,
      // Tolerates a row read before the v19 migration ran, which a test
      // reshaping the schema backwards can produce.
      colorIndex: (map['color_index'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'position': position,
      'created_at': createdAt,
      'color_index': colorIndex,
    };
  }

  Folder copyWith({
    int? id,
    String? name,
    int? position,
    int? createdAt,
    int? colorIndex,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      colorIndex: colorIndex ?? this.colorIndex,
    );
  }
}
