// Regression cover for the two stale-tab defects found in the on-device
// sweep of 2026-08-21.
//
// All four main screens live in a kept-alive IndexedStack, so a screen that
// loads in initState never reloads on a plain tab switch. Confirmed on a
// Pixel 11 Pro: bookmarking an article from the feed's radial menu wrote the
// row, but the Bookmarks tab kept showing "No bookmarks yet" until a
// pull-to-refresh or an app restart.
// (The sibling defect — adding a feed not reaching the article list — is
// covered by FeedsChangedNotifier and feeds_changed_notifier_test.dart,
// which uses a record/consume design rather than a broadcast because the
// feed screen is by definition off-screen when those writes happen.)
//
// This one is fixed by a broadcast singleton, following the pattern
// ReadStateNotifier already established for read state.
//
// What these tests pin is the *contract the screens rely on*, in particular
// SavedStateNotifier carrying the changed row with the signal. That payload
// is what makes the signal self-cancelling: the screen that made the write
// compares the broadcast value against what it already shows, sees no
// discrepancy, and skips the reload — which is why bookmarking from the feed
// no longer rebuilds the feed list and jogs the scroll position.
//
// Plain test(), not testWidgets(): these are pure ChangeNotifiers, and the
// screens that consume them build real repositories, which this codebase
// never combines with testWidgets() (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/saved_state_notifier.dart';

void main() {
  group('SavedStateNotifier', () {
    test('delivers the changed article id and its new value', () {
      final seen = <(int?, bool)>[];
      void listener() => seen.add((
            SavedStateNotifier.instance.articleId,
            SavedStateNotifier.instance.saved,
          ));

      SavedStateNotifier.instance.addListener(listener);
      addTearDown(
          () => SavedStateNotifier.instance.removeListener(listener));

      SavedStateNotifier.instance.articleSavedStateChanged(42, saved: true);
      SavedStateNotifier.instance.articleSavedStateChanged(42, saved: false);
      SavedStateNotifier.instance.articleSavedStateChanged(7, saved: true);

      expect(seen, [(42, true), (42, false), (7, true)]);
    });

    test('payload is readable at notification time, not after the fact', () {
      // The screens read `articleId`/`saved` synchronously inside their
      // listener. If the fields were set after notifyListeners(), every
      // listener would act on the *previous* change — silently bookmarking
      // the wrong row in the feed's in-memory list.
      int? idAtCallback;
      bool? savedAtCallback;
      void listener() {
        idAtCallback = SavedStateNotifier.instance.articleId;
        savedAtCallback = SavedStateNotifier.instance.saved;
      }

      SavedStateNotifier.instance.addListener(listener);
      addTearDown(
          () => SavedStateNotifier.instance.removeListener(listener));

      SavedStateNotifier.instance.articleSavedStateChanged(99, saved: true);

      expect(idAtCallback, 99);
      expect(savedAtCallback, isTrue);
    });

    test('repeats a signal even when the value is unchanged', () {
      // Two screens can write the same value in a row (bookmark in the feed,
      // then unbookmark and re-bookmark). The notifier must not dedupe, or
      // the second screen never hears about the second write.
      var calls = 0;
      void listener() => calls++;

      SavedStateNotifier.instance.addListener(listener);
      addTearDown(
          () => SavedStateNotifier.instance.removeListener(listener));

      SavedStateNotifier.instance.articleSavedStateChanged(5, saved: true);
      SavedStateNotifier.instance.articleSavedStateChanged(5, saved: true);

      expect(calls, 2);
    });

    test('a removed listener stops hearing signals', () {
      // Screens remove their listener in dispose; a leak here would keep a
      // disposed State reachable and calling setState.
      var calls = 0;
      void listener() => calls++;

      SavedStateNotifier.instance.addListener(listener);
      SavedStateNotifier.instance.articleSavedStateChanged(1, saved: true);
      SavedStateNotifier.instance.removeListener(listener);
      SavedStateNotifier.instance.articleSavedStateChanged(2, saved: true);

      expect(calls, 1);
    });
  });
}
