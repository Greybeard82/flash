class Folder {
  final int? id;
  final String name;
  final int position;
  final int createdAt;

  const Folder({
    this.id,
    required this.name,
    required this.position,
    required this.createdAt,
  });

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as int?,
      name: map['name'] as String,
      position: map['position'] as int,
      createdAt: map['created_at'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'position': position,
      'created_at': createdAt,
    };
  }

  Folder copyWith({
    int? id,
    String? name,
    int? position,
    int? createdAt,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
