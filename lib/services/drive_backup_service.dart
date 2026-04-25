import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../models/feed.dart';
import '../models/folder.dart';
import '../models/keyword_block.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/keyword_repository.dart';

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

  GoogleSignInAccount? get currentUser => _signIn.currentUser;

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

    final folderRepo = FolderRepository();
    final feedRepo = FeedRepository();
    final keywordRepo = KeywordRepository();

    // Wipe existing (folder delete cascades to feeds + articles via FK)
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

    // Re-insert folders, capturing name → new id
    final nameToId = <String, int>{};
    for (final f in (data['folders'] as List)) {
      final inserted = await folderRepo.insert(Folder(
        name: f['name'] as String,
        position: f['position'] as int? ?? 0,
        createdAt: now,
      ));
      nameToId[f['name'] as String] = inserted.id!;
    }

    // Re-insert feeds
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

    // Re-insert keywords
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
