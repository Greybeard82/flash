import 'package:flutter/foundation.dart';

/// Immutable unread totals driving every folder tab badge.
class UnreadCounts {
  final int all;
  final Map<int, int> byFolder;

  const UnreadCounts({required this.all, required this.byFolder});

  const UnreadCounts.empty()
      : all = 0,
        byFolder = const {};

  factory UnreadCounts.fromRepository({
    required int total,
    required Map<int, int> byFolder,
  }) {
    return UnreadCounts(all: total, byFolder: byFolder);
  }

  int forFolder(int folderId) => byFolder[folderId] ?? 0;

  UnreadCounts applyRead(int? folderId) {
    final newAll = (all - 1).clamp(0, all);
    if (folderId == null) {
      return UnreadCounts(all: newAll, byFolder: byFolder);
    }
    final current = forFolder(folderId);
    final newByFolder = Map<int, int>.of(byFolder);
    newByFolder[folderId] = (current - 1).clamp(0, current);
    return UnreadCounts(all: newAll, byFolder: newByFolder);
  }

  UnreadCounts applyUnread(int? folderId) {
    final newAll = all + 1;
    if (folderId == null) {
      return UnreadCounts(all: newAll, byFolder: byFolder);
    }
    final newByFolder = Map<int, int>.of(byFolder);
    newByFolder[folderId] = forFolder(folderId) + 1;
    return UnreadCounts(all: newAll, byFolder: newByFolder);
  }

  UnreadCounts applyManyRead(Iterable<int?> folderIds) {
    var result = this;
    for (final id in folderIds) {
      result = result.applyRead(id);
    }
    return result;
  }

  UnreadCounts clearedAll() {
    final newByFolder = {for (final id in byFolder.keys) id: 0};
    return UnreadCounts(all: 0, byFolder: newByFolder);
  }

  UnreadCounts clearedFolder(int folderId) {
    final folderCount = forFolder(folderId);
    final newByFolder = Map<int, int>.of(byFolder);
    newByFolder[folderId] = 0;
    final newAll = (all - folderCount).clamp(0, all);
    return UnreadCounts(all: newAll, byFolder: newByFolder);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UnreadCounts &&
        other.all == all &&
        mapEquals(other.byFolder, byFolder);
  }

  @override
  int get hashCode => Object.hash(all, Object.hashAllUnordered(
      byFolder.entries.map((e) => Object.hash(e.key, e.value))));
}
