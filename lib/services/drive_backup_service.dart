import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../models/feed.dart';
import '../models/folder.dart';
import '../models/keyword_block.dart';
import 'backup_serializer.dart';

class DriveBackupService {
  static const _fileName = 'flash_backup.json';
  static const _scopes = [drive.DriveApi.driveAppdataScope];

  final _signIn = GoogleSignIn(scopes: _scopes);

  /// Try to restore a previously signed-in session silently.
  Future<GoogleSignInAccount?> signInSilently() => _signIn.signInSilently();

  /// Full interactive sign-in.
  Future<GoogleSignInAccount?> signIn() => _signIn.signIn();

  Future<void> signOut() async {
    await _signIn.disconnect();
  }

  Future<drive.DriveApi?> _getApi() async {
    final account = _signIn.currentUser ?? await _signIn.signInSilently();
    if (account == null) return null;
    final headers = await account.authHeaders;
    return drive.DriveApi(_AuthClient(headers));
  }

  Future<String?> _findFileId(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName' and trashed = false",
      $fields: 'files(id)',
    );
    return list.files?.firstOrNull?.id;
  }

  /// Back up folders, feeds and keywords to Google Drive.
  Future<DateTime> backup({
    required List<Folder> folders,
    required List<Feed> feeds,
    required List<KeywordBlock> keywords,
  }) async {
    final api = await _getApi();
    if (api == null) throw Exception('Not signed in to Google');

    final now = DateTime.now();
    final data = BackupSerializer.toMap(folders: folders, feeds: feeds, keywords: keywords);
    data['backedUpAt'] = now.millisecondsSinceEpoch;

    final bytes = utf8.encode(jsonEncode(data));
    final media = drive.Media(Stream.fromIterable([bytes]), bytes.length);

    final existingId = await _findFileId(api);
    if (existingId != null) {
      await api.files.update(drive.File(), existingId, uploadMedia: media);
    } else {
      final file = drive.File()
        ..name = _fileName
        ..parents = ['appDataFolder'];
      await api.files.create(file, uploadMedia: media);
    }

    return now;
  }

  /// Restore folders, feeds and keywords from Drive.
  /// Wipes existing data first — articles will be re-fetched on next refresh.
  Future<int> restore() async {
    final api = await _getApi();
    if (api == null) throw Exception('Not signed in to Google');

    final fileId = await _findFileId(api);
    if (fileId == null) throw Exception('No backup found in Drive');

    final response = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return BackupSerializer.restoreFromMap(data);
  }
}

class _AuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final _inner = http.Client();

  _AuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
