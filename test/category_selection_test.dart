// Creating a category selects it — and nothing else does.
//
// **The feature is one line. The test file is this long because the feature
// is not the risk.** Landing the user in the category they just named is a
// `Scrollable.ensureVisible` and a tab index. The risk is the other four
// paths that create folders: an OPML file, the starter pack, a backup
// restore, and onboarding. All four go through `FolderRepository.insert`,
// all four fire `FeedsChangedNotifier`, and any of them hijacking the
// article list's selection would be a worse bug than the one being fixed —
// an import of fifty folders yanking the list into an arbitrary one of them,
// with no way for the user to tell why.
//
// So the distinction is declared, not inferred: `categoryCreatedByUser` is
// called from the one place that knows a person typed a name and pressed a
// button, and `FolderRepository.insert` — which cannot tell the paths apart,
// because it sees a row and not an intent — is left alone.
//
// These tests drive the REAL import, the REAL starter pack and the REAL
// restore over sqflite FFI rather than asserting that the source does not
// contain a string. A future contributor who wires the selection into the
// repository "to cover all the cases" gets three red tests naming the
// reason, which is the only form of this comment that survives being unread.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/repositories/feed_repository.dart';
import 'package:flash/repositories/folder_repository.dart';
import 'package:flash/services/backup_serializer.dart';
import 'package:flash/services/feeds_changed_notifier.dart';
import 'package:flash/services/opml_service.dart';
import 'package:flash/services/starter_pack_service.dart';

late FolderRepository _folderRepo;
late FeedRepository _feedRepo;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _folderRepo = FolderRepository();
  _feedRepo = FeedRepository();
  FeedsChangedNotifier.instance.reset();
}

/// Source with comments stripped as blocks, per harness rule 10.4 — this
/// file's own prose names every symbol it searches for.
String _code(String path) {
  final raw = File(path).readAsStringSync();
  return const LineSplitter()
      .convert(raw.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' '))
      .where((l) =>
          !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
      .join('\n');
}

Future<Folder> _insert(String name, int position) => _folderRepo.insert(
      Folder(
        name: name,
        position: position,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

void main() {
  setUp(_setUp);
  tearDown(() async {
    FeedsChangedNotifier.instance.reset();
    await AppDatabase.instance.close();
  });

  group('the signal a person just made one', () {
    test('creating one records it, and the id comes back once', () {
      FeedsChangedNotifier.instance.categoryCreatedByUser(42);
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), 42);
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull,
          reason: 'single-consumer, like consume(), so two screens cannot '
              'both act on one creation');
    });

    test('it also queues a structural change, so the list is woken', () {
      FeedsChangedNotifier.instance.categoryCreatedByUser(7);
      expect(FeedsChangedNotifier.instance.pending, FeedsChange.structureOnly);
    });

    test('the last one wins when two are made before a look', () {
      // Not a queue. Two categories created back to back before the article
      // list is next seen: landing in the second is the defensible answer,
      // and landing in both is not a thing.
      FeedsChangedNotifier.instance
        ..categoryCreatedByUser(1)
        ..categoryCreatedByUser(2);
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), 2);
    });

    test('reset clears it, which is what onboarding relies on', () {
      FeedsChangedNotifier.instance.categoryCreatedByUser(9);
      FeedsChangedNotifier.instance.reset();
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull);
    });
  });

  group('every OTHER reason the notifier fires selects nothing', () {
    test('a plain structure change does not', () {
      FeedsChangedNotifier.instance.structureChanged();
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull);
    });

    test('a feed being added does not', () {
      FeedsChangedNotifier.instance.feedAdded();
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull);
    });

    test('FolderRepository.insert itself does not — this is the whole design',
        () async {
      // The repository is the choke point every creation path goes through.
      // If the selection were wired here it would be right once and wrong
      // four times.
      await _insert('Tech', 0);
      expect(FeedsChangedNotifier.instance.pending,
          FeedsChange.structureOnly,
          reason: 'it must still announce the structure change');
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull,
          reason: 'but it cannot know whether a person asked for it');
    });

    test('rename, delete and reorder do not', () async {
      final folder = await _insert('Tech', 0);
      FeedsChangedNotifier.instance.reset();

      await _folderRepo.update(folder.copyWith(name: 'Technology'));
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull);

      await _folderRepo.reorder([folder]);
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull);

      await _folderRepo.delete(folder.id!);
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull);
    });
  });

  group('an OPML import creating five folders selects none of them', () {
    test('five created, nothing selected', () async {
      final result = await OpmlService().importEntries([
        for (final name in const ['Tech', 'World', 'Sport', 'Science', 'Culture'])
          OpmlFeedEntry(
            folderName: name,
            title: '$name Daily',
            xmlUrl: 'https://example.com/${name.toLowerCase()}.xml',
          ),
      ]);

      expect(result.foldersCreated, 5, reason: 'the import must have run');
      expect((await _folderRepo.getAll()).length, 5);
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull,
          reason: 'there is no correct one to pick out of five, and picking '
              'an arbitrary one is worse than picking none');
    });

    test('even an import that creates exactly one selects none', () async {
      // The tempting shortcut is "select it when only one was made". It is
      // wrong: a one-folder OPML file is still an import, and the user was in
      // Settings, not naming a category.
      final result = await OpmlService().importEntries([
        OpmlFeedEntry(
          folderName: 'Imported',
          title: 'Ars Technica',
          xmlUrl: 'https://arstechnica.com/feed',
        ),
      ]);

      expect(result.foldersCreated, 1);
      expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull);
    });
  });

  test('the starter pack selects none', () async {
    final result = await StarterPackService().addCategories(
      ['news', 'tech'],
      {'news': 'World News', 'tech': 'Tech'},
    );

    expect(result.foldersCreated, greaterThan(0),
        reason: 'the seeding must have run for this to prove anything');
    expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull);
  });

  test('a backup restore selects none', () async {
    final folder = await _insert('Tech', 0);
    final feed = await _feedRepo.insert(Feed(
      folderId: folder.id!,
      title: 'Ars Technica',
      url: 'https://arstechnica.com/feed',
      position: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    final snapshot = BackupSerializer.toMap(
      folders: [folder],
      feeds: [feed],
      keywords: [],
    );
    FeedsChangedNotifier.instance.reset();

    await BackupSerializer.restoreFromMap(snapshot);

    expect((await _folderRepo.getAll()).length, 1,
        reason: 'the restore must have run');
    expect(FeedsChangedNotifier.instance.pending, FeedsChange.structureOnly,
        reason: 'it still announces the structure change');
    expect(FeedsChangedNotifier.instance.takeUserCreatedCategory(), isNull,
        reason: 'a restore rebuilds a library; none of it is new to the user');
  });

  group('what a person sees when they land in the empty thing they made', () {
    // Source assertions, in the same shape as empty_state_roles_test.dart and
    // for the same reason: reaching this branch through a pumped FeedScreen
    // needs a database, a shell and a network stub, and what matters here is
    // which of three empty states the code chooses.
    final code = _code('lib/screens/feed_screen.dart');

    test('a category with no feeds is not told it is caught up', () {
      // "No new articles. You're all caught up." is a double tick
      // congratulating someone on having read a folder that has never held
      // anything. It is the first screen after naming a first category now
      // that creating one selects it, so it had to stop being that.
      expect(code, contains('_selectedFolderHasNoFeeds'));
      final branch = code.indexOf('if (_articles.isEmpty && _selectedFolderHasNoFeeds)');
      final caughtUp = code.indexOf('l10n.noNewArticles');
      expect(branch, greaterThan(-1));
      expect(branch, lessThan(caughtUp),
          reason: 'the feedless case has to be tested BEFORE the caught-up '
              'case, or it never runs');
    });

    test('it says nothing here yet, and offers the thing to do about it', () {
      expect(code, contains('l10n.nothingHereYet'));
      expect(code, contains('l10n.addAFeedButton'));
      expect(code, contains('onPressed: widget.onNavigateToFeeds'));
    });

    test('it does not claim this is their first feed', () {
      // addFirstFeed is "Add your first feed to get started", which is a lie
      // to someone with twenty filed in five other categories.
      final start = code.indexOf('_selectedFolderHasNoFeeds)');
      final end = code.indexOf('l10n.noNewArticles');
      expect(code.substring(start, end), isNot(contains('addFirstFeed')));
    });

    test('the emptiness is per-category, not the app-wide _hasFeeds flag', () {
      final getter = RegExp(
              r'bool get _selectedFolderHasNoFeeds \{(.*?)\n  \}',
              dotAll: true)
          .firstMatch(code);
      expect(getter, isNotNull);
      final body = getter!.group(1)!;
      expect(body, isNot(contains('_hasFeeds')),
          reason: 'app-wide and per-category are different questions');
      expect(body, contains('_feedFolderId'));
      expect(body, contains('_selectedTabIndex == 0'),
          reason: 'All is never "a category with no feeds"');
    });
  });

  group('where the distinction lives, so it cannot drift', () {
    test('exactly one call site declares the intent', () {
      final hits = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path.endsWith('feeds_changed_notifier.dart')) continue;
        if (_code(path).contains('categoryCreatedByUser(')) hits.add(path);
      }
      expect(hits, ['lib/screens/feeds_screen.dart'],
          reason: 'a second caller is how this stops meaning what it says');
    });

    test('the field is written in exactly the two places its doc claims', () {
      final code = _code('lib/services/feeds_changed_notifier.dart');
      final writes = RegExp(r'_userCreatedFolderId\s*=').allMatches(code);
      expect(writes, hasLength(3),
          reason: 'categoryCreatedByUser sets it; takeUserCreatedCategory and '
              'reset clear it. A fourth assignment means _record or some new '
              'method can move the user selection.');

      // _record is the path every OTHER fire takes. It must not touch it.
      final record = RegExp(r'void _record\(FeedsChange change\)\s*\{(.*?)\n  \}',
              dotAll: true)
          .firstMatch(code);
      expect(record, isNotNull);
      expect(record!.group(1), isNot(contains('_userCreatedFolderId')));
    });

    test('the article list acts on it only through the single-consumer take',
        () {
      final code = _code('lib/screens/feed_screen.dart');
      expect(code, contains('takeUserCreatedCategory()'));
      expect(code, contains('void _selectCreatedFolder(int folderId)'));

      final consume = RegExp(
              r'Future<void> _consumeFeedsChange\(\) async \{(.*?)\n  \}',
              dotAll: true)
          .firstMatch(code);
      expect(consume, isNotNull);
      // Taken BEFORE the early return, or a change consumed a moment earlier
      // by the visibility transition would drop the selection on the floor.
      final body = consume!.group(1)!;
      expect(body.indexOf('takeUserCreatedCategory'),
          lessThan(body.indexOf('if (change == null')),
          reason: 'order matters: both signals ride the same debounce');
      expect(body, contains('change == null && selectFolderId == null'));
    });

    test('nothing about the selection branches on form factor', () {
      // The tablet behaves like the phone because there is no tablet code,
      // not because a second path was written to match. The two screens are
      // never co-visible in any tier — one IndexedStack, one visible child —
      // so the article list learns about this the same way on both.
      final code = _code('lib/screens/feed_screen.dart');
      final method = RegExp(
              r'void _selectCreatedFolder\(int folderId\) \{(.*?)\n  \}',
              dotAll: true)
          .firstMatch(code);
      expect(method, isNotNull);
      final body = method!.group(1)!;
      for (final formFactor in [
        'MediaQuery',
        'kThreeColumnBreakpoint',
        'useRail',
        'ArticleDetailScope',
        'isTV',
      ]) {
        expect(body, isNot(contains(formFactor)), reason: formFactor);
      }
    });
  });
}
