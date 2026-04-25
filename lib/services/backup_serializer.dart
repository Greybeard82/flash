import '../models/feed.dart';
import '../models/folder.dart';
import '../models/keyword_block.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/keyword_repository.dart';

class BackupSerializer {
  /// Serialises folders, feeds and keywords to the shared Flash backup format.
  static Map<String, dynamic> toMap({
    required List<Folder> folders,
    required List<Feed> feeds,
    required List<KeywordBlock> keywords,
  }) {
    final folderMap = {for (final f in folders) f.id!: f.name};
    return {
      'version': 1,
      'backedUpAt': DateTime.now().millisecondsSinceEpoch,
      'folders': folders
          .map((f) => {'name': f.name, 'position': f.position})
          .toList(),
      'feeds': feeds
          .map((f) => {
                'title': f.title,
                'url': f.url,
                'folderName': folderMap[f.folderId] ?? '',
                'position': f.position,
                'siteUrl': f.siteUrl,
                'description': f.description,
              })
          .toList(),
      'keywords': keywords
          .map((k) => {'keyword': k.keyword, 'wholeWord': k.wholeWord})
          .toList(),
    };
  }

  /// Validates that [data] is a well-formed Flash backup map.
  static void validate(Map<String, dynamic> data) {
    if ((data['version'] as int?) != 1 ||
        data['folders'] == null ||
        data['feeds'] == null) {
      throw const FormatException('Not a valid Flash backup file');
    }
  }

  /// Wipes all existing folders/feeds/keywords then restores from [data].
  /// Returns the number of feeds imported.
  static Future<int> restoreFromMap(Map<String, dynamic> data) async {
    validate(data);

    final folderRepo = FolderRepository();
    final feedRepo = FeedRepository();
    final keywordRepo = KeywordRepository();

    // Wipe existing — folder cascade deletes feeds + articles via FK
    for (final f in await folderRepo.getAll()) {
      await folderRepo.delete(f.id!);
    }
    for (final f in await feedRepo.getAll()) {
      await feedRepo.delete(f.id!);
    }
    for (final k in await keywordRepo.getAll()) {
      await keywordRepo.delete(k.id!);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final nameToId = <String, int>{};

    for (final f in (data['folders'] as List)) {
      final inserted = await folderRepo.insert(Folder(
        name: f['name'] as String,
        position: f['position'] as int? ?? 0,
        createdAt: now,
      ));
      nameToId[f['name'] as String] = inserted.id!;
    }

    int feedCount = 0;
    for (final f in (data['feeds'] as List)) {
      final folderName = f['folderName'] as String? ?? '';
      final folderId = nameToId[folderName];
      if (folderId == null) continue;
      await feedRepo.insert(Feed(
        folderId: folderId,
        title: f['title'] as String,
        url: f['url'] as String,
        siteUrl: f['siteUrl'] as String?,
        description: f['description'] as String?,
        position: f['position'] as int? ?? 0,
        createdAt: now,
      ));
      feedCount++;
    }

    for (final k in (data['keywords'] as List? ?? [])) {
      await keywordRepo.insert(KeywordBlock(
        keyword: k['keyword'] as String,
        wholeWord: k['wholeWord'] as bool? ?? false,
        createdAt: now,
      ));
    }

    return feedCount;
  }
}
