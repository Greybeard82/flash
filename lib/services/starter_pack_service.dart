import '../data/starter_pack.dart';
import '../models/feed.dart';
import '../models/folder.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import 'favicon_service.dart';

/// What one seeding run actually did.
///
/// `feedsSkipped` is not an error count. A skip means the user already has
/// that feed, which is the normal outcome of opening the sheet a second time,
/// and the banner says "No new feeds added" rather than complaining.
class StarterPackResult {
  final int foldersCreated;
  final int feedsAdded;
  final int feedsSkipped;

  /// Exactly the feeds this run inserted, with their new ids — what
  /// [StarterPackService.warmFavicons] needs, and nothing that was skipped.
  final List<Feed> addedFeeds;

  const StarterPackResult({
    required this.foldersCreated,
    required this.feedsAdded,
    required this.feedsSkipped,
    required this.addedFeeds,
  });
}

/// Seeds the starter pack into the database.
///
/// Writes only — no network. That is the whole reason this finishes fast
/// enough to run behind an onboarding button: the fetch that fills the
/// categories is the one `FeedScreen` already runs on its own, triggered by
/// the `FeedsChangedNotifier.feedAdded()` that `FeedRepository.insert` pings
/// from inside. Fetching here as well would be a second network pass for the
/// same articles.
///
/// Every rule below exists to make a second run harmless. The pack is offered
/// from onboarding *and* from both empty states, so "the user already has
/// some of this" is the expected case, not the edge one.
class StarterPackService {
  final FeedRepository _feedRepo;
  final FolderRepository _folderRepo;
  final FaviconService _faviconService;

  StarterPackService({
    FeedRepository? feedRepo,
    FolderRepository? folderRepo,
    FaviconService? faviconService,
  })  : _feedRepo = feedRepo ?? FeedRepository(),
        _folderRepo = folderRepo ?? FolderRepository(),
        _faviconService = faviconService ?? FaviconService();

  /// Creates the categories in [categoryIds] and the feeds inside them.
  ///
  /// [folderNameById] is the localised display name per category id, resolved
  /// by the caller from the ARB. Folder names are written in the device locale
  /// *at seeding time* and from then on are ordinary user data — renameable,
  /// and never re-translated when the device language changes. Anything else
  /// would mean a category the user had renamed silently reverting.
  ///
  /// Selected categories are seeded in pack order rather than the order they
  /// were ticked, so the result always reads the same way down the Categories
  /// screen.
  Future<StarterPackResult> addCategories(
    List<String> categoryIds,
    Map<String, String> folderNameById,
  ) async {
    final selected = categoryIds.toSet();
    final existingFolders = await _folderRepo.getAll();

    var foldersCreated = 0;
    var feedsAdded = 0;
    var feedsSkipped = 0;
    final addedFeeds = <Feed>[];

    for (final category in kStarterPack) {
      if (!selected.contains(category.id)) continue;
      final name = folderNameById[category.id];
      if (name == null) continue;

      // Reuse before create. Someone who already keeps a "world news"
      // category should get the feeds put in it, not a second one beside it
      // with different capitalisation.
      final key = name.trim().toLowerCase();
      var folder = _firstWhereOrNull(
          existingFolders, (f) => f.name.trim().toLowerCase() == key);

      if (folder == null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        folder = await _folderRepo.insert(Folder(
          name: name,
          // After everything already there, so seeding never reshuffles a
          // list the user has arranged.
          position: await _folderRepo.getNextPosition(),
          createdAt: now,
        ));
        existingFolders.add(folder);
        foldersCreated++;
      }

      // Read once per folder rather than once per feed: a reused folder may
      // already hold feeds, and the new ones go after them.
      var nextPosition = (await _feedRepo.getByFolder(folder.id!)).length;

      for (final starter in category.feeds) {
        // `feeds.url` is UNIQUE, so this is a correctness check and not just
        // a courtesy — but the reason it is a *skip* rather than a move is
        // that the user may have deliberately filed this feed somewhere else
        // under a name of their own. Seeding must not undo that.
        if (await _feedRepo.getByUrl(starter.url) != null) {
          feedsSkipped++;
          continue;
        }

        final inserted = await _feedRepo.insert(Feed(
          folderId: folder.id!,
          title: starter.title,
          url: starter.url,
          siteUrl: starter.siteUrl,
          description: starter.description,
          position: nextPosition++,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        addedFeeds.add(inserted);
        feedsAdded++;
      }
    }

    return StarterPackResult(
      foldersCreated: foldersCreated,
      feedsAdded: feedsAdded,
      feedsSkipped: feedsSkipped,
      addedFeeds: addedFeeds,
    );
  }

  /// Fetches and caches a favicon per feed, best effort.
  ///
  /// Deliberately not awaited by any caller: this is a dozen HTTP round trips
  /// to Google's favicon service, and making the user watch them finish before
  /// the first article appears would trade the whole point of the starter pack
  /// for some icons. Failures are swallowed — `FeedCard` falls back to a
  /// monogram, so a missing icon costs nothing.
  Future<void> warmFavicons(List<Feed> feeds) async {
    for (final feed in feeds) {
      if (feed.id == null) continue;
      try {
        final host = Uri.tryParse(feed.siteUrl ?? feed.url)?.host ?? '';
        if (host.isEmpty) continue;
        final path = await _faviconService.fetchAndCache(host, feed.id!);
        if (path != null) await _feedRepo.updateFaviconPath(feed.id!, path);
      } catch (_) {
        // Best effort, by design.
      }
    }
  }

  /// `firstWhereOrNull` without taking a dependency on `collection` for it.
  static T? _firstWhereOrNull<T>(List<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }
}
