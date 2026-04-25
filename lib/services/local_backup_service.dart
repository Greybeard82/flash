import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/feed.dart';
import '../models/folder.dart';
import '../models/keyword_block.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/keyword_repository.dart';

class LocalBackupService {
  /// Serialises folders/feeds/keywords to the same JSON format as Drive backup,
  /// writes it to a temp file, then opens the system share sheet so the user
  /// can save it to Downloads, email it, etc.
  static Future<void> exportBackup({
    required List<Folder> folders,
    required List<Feed> feeds,
    required List<KeywordBlock> keywords,
  }) async {
    final folderMap = {for (final f in folders) f.id!: f.name};
    final now = DateTime.now();

    final data = {
      'version': 1,
      'backedUpAt': now.millisecondsSinceEpoch,
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

    final json = const JsonEncoder.withIndent('  ').convert(data);

    // Write to a temp file the share sheet can attach
    final tmp = await getTemporaryDirectory();
    final dateStr = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final file = File('${tmp.path}/flash_backup_$dateStr.json');
    await file.writeAsString(json, encoding: utf8);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Flash backup $dateStr',
    );
  }

  /// Opens the system file picker, reads the selected JSON file, and
  /// re-inserts folders/feeds/keywords. Returns the number of feeds imported.
  /// Throws if the file is not a valid Flash backup.
  static Future<int> importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) {
      return -1; // User cancelled
    }

    final path = result.files.first.path;
    if (path == null) throw Exception('Could not read selected file');

    final content = await File(path).readAsString(encoding: utf8);
    final data = jsonDecode(content) as Map<String, dynamic>;

    if ((data['version'] as int?) != 1 || data['folders'] == null) {
      throw const FormatException('Not a valid Flash backup file');
    }

    final folderRepo = FolderRepository();
    final feedRepo = FeedRepository();
    final keywordRepo = KeywordRepository();

    // Wipe existing (folder cascade deletes feeds + articles)
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
