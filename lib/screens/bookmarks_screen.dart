import 'package:flutter/material.dart';
import '../utils/diag_log.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../repositories/article_repository.dart';
import '../services/loading_controller.dart';
import '../services/read_state_notifier.dart';
import '../services/saved_state_notifier.dart';
import '../services/share_service.dart';
import '../widgets/article_card.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final _articleRepo = ArticleRepository();
  final _shareService = ShareService();

  List<Article> _articles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // This screen is kept alive in the IndexedStack, so initState runs once
    // per app launch. Without this listener a bookmark made anywhere else
    // stayed invisible here until a pull-to-refresh or a restart.
    SavedStateNotifier.instance.addListener(_onSavedStateChanged);
    _load();
  }

  @override
  void dispose() {
    SavedStateNotifier.instance.removeListener(_onSavedStateChanged);
    super.dispose();
  }

  /// Membership of this list is exactly the saved flag, so a change to it
  /// means a reload — unless the list already reflects the new value, which
  /// is the case when the change came from this screen's own [_toggleSaved].
  void _onSavedStateChanged() {
    if (!mounted) return;
    final id = SavedStateNotifier.instance.articleId;
    if (id == null) return;
    final present = _articles.any((a) => a.id == id);
    if (present == SavedStateNotifier.instance.saved) return;
    _load();
  }

  Future<void> _load() async {
    await LoadingController.instance.run(() async {
      final articles = await _articleRepo.getSaved();
      if (mounted) {
        setState(() {
          _articles = articles;
          _loading = false;
        });
      }
    }, label: 'Loading');
  }

  Future<void> _openArticle(Article article) async {
    if (article.id != null) {
      DiagLog.read(id: article.id!, trigger: 'tap:bookmarks', offset: -1);
    await _articleRepo.markAsRead(article.id!);
      ReadStateNotifier.instance.articleReadStateChanged();
      if (mounted) {
        setState(() {
          _articles = _articles
              .map((a) => a.id == article.id ? a.copyWith(isRead: true) : a)
              .toList();
        });
      }
    }

    if (!mounted) return;
    final uri = Uri.tryParse(article.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _toggleSaved(Article article) async {
    if (article.id == null) return;
    await LoadingController.instance.run(() async {
      await _articleRepo.setSaved(article.id!, saved: false);
      HapticFeedback.lightImpact();
      if (mounted) {
        setState(() => _articles.removeWhere((a) => a.id == article.id));
      }
      // After the local removal, so this screen's own listener sees a list
      // that already agrees. FeedScreen may be holding the same article and
      // needs the flag cleared for its radial menu.
      SavedStateNotifier.instance
          .articleSavedStateChanged(article.id!, saved: false);
    }, label: 'Removing bookmark');
  }

  Future<void> _markRead(Article article) async {
    if (article.id == null) return;
    DiagLog.read(id: article.id!, trigger: 'tap:bookmarks', offset: -1);
    await _articleRepo.markAsRead(article.id!);
    ReadStateNotifier.instance.articleReadStateChanged();
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {
        _articles = _articles
            .map((a) => a.id == article.id ? a.copyWith(isRead: true) : a)
            .toList();
      });
    }
  }

  Future<void> _markUnread(Article article) async {
    if (article.id == null) return;
    await _articleRepo.markAsUnread(article.id!);
    // markAsUnread clears read_at, so the article leaves the show-read window
    // as well as the unread count. Ping so the feed's badges re-query.
    ReadStateNotifier.instance.articleReadStateChanged();
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {
        _articles = _articles
            .map((a) => a.id == article.id ? a.copyWith(isRead: false) : a)
            .toList();
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bookmarks),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _articles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_border_rounded,
                          size: 48,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      Text(
                        l10n.noBookmarks,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _articles.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, i) {
                      final article = _articles[i];
                      return ArticleCard(
                        article: article,
                        onTap: () => _openArticle(article),
                        onMarkRead: () => _markRead(article),
                        onMarkUnread: () => _markUnread(article),
                        onShare: () => _shareService.shareArticle(article),
                        onBookmark: () => _toggleSaved(article),
                      );
                    },
                  ),
                ),
    );
  }
}
