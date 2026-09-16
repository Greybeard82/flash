import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/spinning_refresh_icon.dart';
import '../utils/diag_log.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../repositories/alert_match_repository.dart';
import '../repositories/article_repository.dart';
import '../services/article_opener.dart';
import '../services/loading_controller.dart';
import '../services/read_state_notifier.dart';
import '../theme/app_theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _repo = ArticleRepository();
  final _alertMatchRepo = AlertMatchRepository();
  final _controller = TextEditingController();
  List<Article> _results = [];
  bool _loading = false;
  String _lastQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Rebuild now so the clear button tracks the field. Without this the
    // only rebuild came from the debounced search 350ms later, so the button
    // appeared well after the first keystroke and lingered after a clear.
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query == _lastQuery) return;
    _lastQuery = query;
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final results = await LoadingController.instance
        .run(() => _repo.search(query), label: 'Searching');
    if (mounted && query == _lastQuery) {
      setState(() {
        _results = results;
        _loading = false;
      });
    }
  }

  Future<void> _open(Article article) async {
    if (!article.isRead && article.id != null) {
      DiagLog.read(id: article.id!, trigger: 'tap:search', offset: -1);
      await _repo.markAsRead(article.id!);
      // Mirrored into the alert snapshot, which keeps its own is_read — see
      // the same call in bookmarks_screen.dart.
      await _alertMatchRepo.setRead(article.feedId, article.guid, isRead: true);
      ReadStateNotifier.instance.articleReadStateChanged();
      if (mounted) {
        setState(() {
          _results = _results
              .map((a) => a.id == article.id ? a.copyWith(isRead: true) : a)
              .toList();
        });
      }
    }

    if (!mounted) return;
    await openArticle(context, article);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: l10n.searchArticles,
            border: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      setState(() {});
                      _search('');
                    },
                  )
                : null,
          ),
        ),
      ),
      body: _loading
          ? Center(
              child: SpinningRefreshIcon(
                  size: 40, color: theme.colorScheme.primary))
          : _lastQuery.isEmpty
              // Was SizedBox.shrink(), which rendered a blank screen under a
              // focused field and read as a screen that had failed to load
              // rather than one waiting for input.
              //
              // The shared empty-state shape: a 48dp `illustration` glyph over
              // one line of `onSurfaceVariant` copy. The first attempt at this
              // used the glyph alone, on the grounds that the only true
              // sentence was already on screen as the field's hint —
              // `empty_state_roles_test` rejected it, and rightly: a glyph with
              // no copy under it is the bare state this app has removed
              // everywhere else. The copy says what to do rather than
              // restating the hint.
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 48,
                          color: theme.flashColors.illustration,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.searchPrompt,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _results.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noSearchResults(_lastQuery),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          // Full-bleed: this is an article list.
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = _results[i];
                        return ListTile(
                          title: Text(
                            a.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            // 6.3: a read search result follows the card,
                            // elementwise. Title to onSurfaceRead, source to
                            // onSurfaceMuted, and the weight held at w600
                            // either way.
                            //
                            // The weight is the part worth stating. This read
                            // w400 when read, and lighter glyphs are narrower,
                            // so a title near the two-line wrap boundary
                            // reflowed the moment it was marked read. That is
                            // the bug article_card_read_colour_test.dart was
                            // written for; the same list, the same trap.
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: a.isRead
                                  ? theme.flashColors.onSurfaceRead
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            a.feedTitle ?? '',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: a.isRead
                                  ? theme.flashColors.onSurfaceMuted
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          onTap: () => _open(a),
                        );
                      },
                    ),
    );
  }
}
