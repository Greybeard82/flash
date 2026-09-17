// The disappearing category.
//
// Create a category, put a feed in it, go back to the article list, and the
// library has not changed there. Pull to refresh and it all appears. One stale
// view, not two: the feed screen builds its picture once and nothing tells it
// the picture changed.
//
// **The fix that would have been wrong is a reload when the Categories route
// pops.** That works on a phone and does nothing on a tablet, where the
// three-column shell can have the structure change and the article list on
// screen together with no push, no pop and no tab switch to hang it on. A fix
// wired to navigation passes on the Pixel and silently fails on the Lenovo,
// which is the half-fix this project keeps producing.
//
// The right shape was already in the repo and already half-used:
// `FeedsChangedNotifier` both *records* (for a single consumer that decides
// whether to fetch) and *broadcasts* (for anything mounted that is showing the
// structure). `FeedsScreen` has listened to the broadcast since the OPML work.
// `FeedScreen` never did — it had the pull half and not the push half.
//
// These are source assertions on purpose. The behaviour needs a mounted
// FeedScreen with a database, a shell and a network stub; what actually broke
// was a missing subscription, and a missing subscription is exactly what a
// source assertion can see and a mocked widget test would not.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source with comments stripped, per harness rule 10.4 — this file's own
/// prose names every symbol it asserts on.
String _code(String path) {
  final raw = File(path).readAsStringSync();
  final withoutBlocks = raw.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
  return const LineSplitter()
      .convert(withoutBlocks)
      .where((l) =>
          !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
      .join('\n');
}

void main() {
  final feedScreen = _code('lib/screens/feed_screen.dart');
  final feedsScreen = _code('lib/screens/feeds_screen.dart');

  group('the article list hears structure changes wherever it is mounted', () {
    test('FeedScreen subscribes to the broadcast', () {
      expect(
          feedScreen,
          contains(
              'FeedsChangedNotifier.instance.addListener(_onFeedsChangedElsewhere)'),
          reason: 'without this the only route in is an isVisible transition, '
              'which a tablet showing both columns at once may never make');
    });

    test('and unsubscribes, so it does not outlive its route', () {
      expect(
          feedScreen,
          contains(
              'FeedsChangedNotifier.instance.removeListener(_onFeedsChangedElsewhere)'),
          reason: 'a listener on a process-lifetime singleton leaks the whole '
              'screen if it is never removed');
    });

    test('the handler re-enters the existing consume path', () {
      // Deliberately NOT a second re-query of its own. consume() is
      // single-consumer by design: a second consumer would swallow the
      // pending change and the new feed would arrive with no articles.
      final handler = RegExp(
              r'void _onFeedsChangedElsewhere\(\)\s*\{(.*?)\n  \}', dotAll: true)
          .firstMatch(feedScreen);
      expect(handler, isNotNull, reason: 'the handler must exist');
      expect(handler!.group(1), contains('_consumeFeedsChange()'));
      expect(handler.group(1), contains('mounted'),
          reason: 'the notifier outlives the widget, so every callback from '
              'it has to check');
    });

    test('a change deferred by an in-flight fetch gets a second look', () {
      // _consumeFeedsChange bails while a fetch is running and leaves the
      // change queued. Nothing used to come back for it: the broadcast had
      // already fired and a visibility transition might never happen. That is
      // the window the reported bug most likely lands in.
      final refresh = RegExp(
              r'Future<void> _backgroundRefresh\(\{[^}]*\}\) async \{(.*?)\n  \}',
              dotAll: true)
          .firstMatch(feedScreen);
      expect(refresh, isNotNull);
      expect(refresh!.group(1), contains('_consumeFeedsChange()'),
          reason: 'without this the busy guard is a silent drop rather than a '
              'deferral');
    });
  });

  group('what must not regress', () {
    test('FeedsScreen still listens — it is the precedent, not a copy', () {
      expect(
          feedsScreen,
          contains(
              'FeedsChangedNotifier.instance.addListener(_onFeedsChangedElsewhere)'),
          reason: 'Categories had this first, for the same reason: Settings is '
              'a pushed route and an OPML import under it has no visibility '
              'transition coming either');
    });

    test('the visibility transition path is kept, not replaced', () {
      // Belt and belt. The transition still covers the common phone case and
      // costs nothing; the listener covers the cases it cannot see. Removing
      // either leaves a hole that only shows up on one form factor.
      expect(feedScreen, contains('widget.isVisible && !oldWidget.isVisible'));
      expect(feedScreen, contains('_consumeFeedsChange()'));
    });

    test('FeedsScreen does not consume the pending change', () {
      // The comment in FeedsScreen is emphatic and worth a guard: consuming
      // there would swallow the fetch decision that belongs to the Flash tab,
      // and the newly imported feeds would sit there with no articles.
      expect(feedsScreen, isNot(contains('FeedsChangedNotifier.instance.consume')),
          reason: 'consume() is single-consumer and the consumer is FeedScreen');
    });
  });
}
