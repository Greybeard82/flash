import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/feed.dart';
import '../models/folder.dart';
import '../models/keyword_block.dart';
import 'backup_serializer.dart';

class LocalBackupService {
  /// Serialises folders/feeds/keywords to the same JSON format as Drive backup,
  /// writes it to a temp file, then opens the system share sheet so the user
  /// can save it to Downloads, email it, etc.
  static Future<void> exportBackup({
    required List<Folder> folders,
    required List<Feed> feeds,
    required List<KeywordBlock> keywords,
  }) async {
    final now = DateTime.now();
    final data = BackupSerializer.toMap(folders: folders, feeds: feeds, keywords: keywords);

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

    return BackupSerializer.restoreFromMap(data);
  }
}
