import 'package:flutter/widgets.dart';

import '../models/article.dart';

/// Which article the detail pane is showing, in the three-column layout.
///
/// Single source of truth: the pane renders whatever is here, and the
/// article-opening path writes here instead of pushing a route when a pane
/// is present. Deliberately survives section switches — picking Bookmarks
/// while an article is open leaves the article open, which is what a
/// master-detail layout is for.
class ArticleDetailController extends ChangeNotifier {
  Article? _article;

  Article? get article => _article;

  void show(Article article) {
    if (_article?.url == article.url) return;
    _article = article;
    notifyListeners();
  }

  void clear() {
    if (_article == null) return;
    _article = null;
    notifyListeners();
  }
}

/// Marks the subtree that has a detail pane to render into.
///
/// Its presence is the signal, not a width check: the three-column shell
/// installs it, everything else doesn't, so an article tap can ask "is there
/// a pane above me?" without knowing anything about layout breakpoints.
class ArticleDetailScope extends InheritedWidget {
  final ArticleDetailController controller;

  const ArticleDetailScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static ArticleDetailController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ArticleDetailScope>()
      ?.controller;

  @override
  bool updateShouldNotify(ArticleDetailScope oldWidget) =>
      controller != oldWidget.controller;
}
