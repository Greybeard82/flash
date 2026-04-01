import 'package:flutter/material.dart';
import '../models/article.dart';
import '../repositories/article_repository.dart';
import '../services/share_service.dart';
import '../widgets/article_card.dart';
import '../widgets/shimmer_card.dart';
import 'package:url_launcher/url_launcher.dart';

class OpinionsScreen extends StatefulWidget {
  const OpinionsScreen({super.key});

  @override
  State<OpinionsScreen> createState() => _OpinionsScreenState();
}

class _OpinionsScreenState extends State<OpinionsScreen> {
  final _articleRepo = ArticleRepository();
  final _shareService = ShareService();
  List<Article> _articles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final articles = await _articleRepo.getOpinions();
    if (mounted) {
      setState(() {
        _articles = articles;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Opinions'),
        centerTitle: false,
      ),
      body: _loading
          ? ListView.builder(
              itemCount: 6,
              itemBuilder: (_, __) => const ShimmerCard(),
            )
          : _articles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 64,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No opinion articles detected.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _articles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final article = _articles[i];
                      return ArticleCard(
                        article: article,
                        onTap: () => _openArticle(article),
                        onMarkRead: () => _markRead(article),
                        onMarkUnread: () => _markUnread(article),
                        onShare: () => _shareService.shareArticle(article),
                      );
                    },
                  ),
                ),
    );
  }

  Future<void> _openArticle(Article article) async {
    final uri = Uri.tryParse(article.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
    await _articleRepo.markRead(article.id!);
    _load();
  }

  Future<void> _markRead(Article article) async {
    await _articleRepo.markRead(article.id!);
    _load();
  }

  Future<void> _markUnread(Article article) async {
    await _articleRepo.markUnread(article.id!);
    _load();
  }
}
