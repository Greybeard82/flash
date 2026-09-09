import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../models/feed.dart';
import '../models/folder.dart';
import '../models/keyword_block.dart';
import 'backup_serializer.dart';

class LocalBackupService {
  /// The filename proposed to the system file picker.
  ///
  /// Date **and time**, to the minute. Exporting twice in one day is the normal
  /// case — before and after a change the user is unsure about — and a
  /// date-only stamp proposed the same name both times.
  ///
  /// That collision is not merely untidy. file_picker on Android writes over an
  /// existing file *without truncating it*, so a smaller export landing on a
  /// larger one leaves the tail of the previous file behind and produces valid
  /// JSON followed by garbage. Not colliding is the fix; patching the plugin is
  /// not. Pinned by backup_export_naming_test.dart.
  @visibleForTesting
  static String backupFileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'flash_backup_'
        '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}.json';
  }

  /// Serialises folders/feeds/keywords to JSON and opens the system file
  /// picker in *create* mode so the user chooses where it lands — Downloads,
  /// an SD card, Drive, anywhere the Storage Access Framework reaches.
  ///
  /// This deliberately does not use the share sheet. `ACTION_SEND` targets apps
  /// that accept a file, and the phone's own storage is not an app: the sheet
  /// offered Gmail, WhatsApp and Drive, and no way to simply save the file. SAF
  /// via `ACTION_CREATE_DOCUMENT` is the mechanism for that, and `saveFile`
  /// with `bytes` is how file_picker exposes it — the plugin writes the file
  /// natively and hands back the path.
  ///
  /// Returns `true` when the file was written, `false` when the user dismissed
  /// the picker. A cancel is a deliberate act and not an error.
  static Future<bool> exportBackup({
    required List<Folder> folders,
    required List<Feed> feeds,
    required List<KeywordBlock> keywords,
    String? dialogTitle,
  }) async {
    final data =
        BackupSerializer.toMap(folders: folders, feeds: feeds, keywords: keywords);
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = Uint8List.fromList(utf8.encode(json));

    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: backupFileName(DateTime.now()),
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    return path != null;
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
