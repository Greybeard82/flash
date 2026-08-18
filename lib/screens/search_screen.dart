import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../repositories/article_repository.dart';
import '../services/loading_controller.dart';
import '../services/read_state_notifier.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _repo = ArticleRepository();
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
      setState(() { _results = []; _loading = false; });
      return;
    }
    setState(() => _loading = true);
    final results = await LoadingController.instance
        .run(() => _repo.search(query), label: 'Searching');
    if (mounted && query == _lastQuery) {
      setState(() { _results = results; _loading = false; });
    }
  }

  Future<void> _open(Article article) async {
    if (!article.isRead && article.id != null) {
      await _repo.markAsRead(article.id!);
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
    final uri = Uri.tryParse(article.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
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
          ? const Center(child: CircularProgressIndicator())
          : _lastQuery.isEmpty
              ? const SizedBox.shrink()
              : _results.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noSearchResults(_lastQuery),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (_, i) {
                        final a = _results[i];
                        return ListTile(
                          title: Text(
                            a.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: a.isRead ? FontWeight.w400 : FontWeight.w600,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: a.isRead ? 0.5 : 1.0),
                            ),
                          ),
                          subtitle: Text(
                            a.feedTitle ?? '',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          onTap: () => _open(a),
                        );
                      },
                    ),
    );
  }
}
