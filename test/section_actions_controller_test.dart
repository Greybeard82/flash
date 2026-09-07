// The shared store behind the sidebar's contextual actions.
//
// Two things here are easy to get wrong and expensive when they are, so
// both are pinned:
//
//   * Screens register from `build`, and all four of them build every frame
//     because they live in a kept-alive IndexedStack. If registering the
//     same actions again counted as a change, the controller would notify,
//     the sidebar would rebuild, the screens would register again, and the
//     app would spin. So an unchanged registration must be silent — even
//     though the closures inside it are new objects each time.
//   * The actions are keyed by section. A single slot would end up holding
//     whichever screen rebuilt last rather than the one on screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/services/section_actions_controller.dart';

SectionAction _action(String label,
        {IconData icon = Icons.refresh_rounded,
        bool enabled = true,
        bool busy = false}) =>
    SectionAction(
      icon: icon,
      label: label,
      busy: busy,
      // A fresh closure every call, deliberately — that is what a rebuild
      // produces, and what the controller must not mistake for a change.
      onPressed: enabled ? () {} : null,
    );

void main() {
  final controller = SectionActionsController.instance;

  setUp(() {
    // Synchronous notifications here: the real path defers to after the
    // frame, which needs a frame pipeline these tests deliberately do not
    // have. What is under test is when it decides to notify, not the
    // scheduler it hands that decision to.
    SectionActionsController.notifyImmediatelyForTesting = true;
    controller.resetForTesting();
  });

  tearDown(() {
    SectionActionsController.notifyImmediatelyForTesting = false;
  });

  group('what the sidebar reads', () {
    test('starts empty', () {
      expect(controller.actions, isEmpty);
    });

    test('shows the current section, not whichever registered last', () {
      controller.setFor(kSectionFlash, [_action('Refresh')]);
      controller.setFor(kSectionBookmarks, [_action('Mark all read')]);
      controller.setFor(kSectionAlerts, [_action('Add'), _action('Mark')]);

      // Flash is selected by default.
      expect(controller.actions.map((a) => a.label), ['Refresh']);
    });

    test('switching section swaps the actions', () {
      controller.setFor(kSectionFlash, [_action('Refresh')]);
      controller.setFor(kSectionAlerts, [_action('Add'), _action('Mark')]);

      controller.selectSection(kSectionAlerts);
      expect(controller.actions.map((a) => a.label), ['Add', 'Mark']);

      controller.selectSection(kSectionFlash);
      expect(controller.actions.map((a) => a.label), ['Refresh']);
    });

    test('a section that registered nothing shows nothing', () {
      controller.setFor(kSectionFlash, [_action('Refresh')]);
      controller.selectSection(kSectionCategories);
      expect(controller.actions, isEmpty,
          reason: 'no stale actions left over from the previous section');
    });

    test('a section can go from having actions to having none', () {
      // Bookmarks' entry disappears when nothing is unread.
      controller.selectSection(kSectionBookmarks);
      controller.setFor(kSectionBookmarks, [_action('Mark all read')]);
      expect(controller.actions, hasLength(1));

      controller.setFor(kSectionBookmarks, const []);
      expect(controller.actions, isEmpty);
    });
  });

  group('re-registering the same actions is silent', () {
    test('an identical set does not notify', () {
      controller.setFor(kSectionFlash, [_action('Refresh')]);

      var notifications = 0;
      void listener() => notifications++;
      controller.addListener(listener);
      addTearDown(() => controller.removeListener(listener));

      // Five rebuilds' worth of the same actions, new closures each time.
      for (var i = 0; i < 5; i++) {
        controller.setFor(kSectionFlash, [_action('Refresh')]);
      }

      expect(notifications, 0,
          reason: 'identical registrations must not notify, or build -> '
              'notify -> rebuild -> build loops forever');
    });

    test('but the newest callback is the one that fires', () {
      var firstFired = false;
      var secondFired = false;

      controller.setFor(kSectionFlash, [
        SectionAction(
            icon: Icons.refresh_rounded,
            label: 'Refresh',
            onPressed: () => firstFired = true),
      ]);
      controller.setFor(kSectionFlash, [
        SectionAction(
            icon: Icons.refresh_rounded,
            label: 'Refresh',
            onPressed: () => secondFired = true),
      ]);

      controller.actions.single.onPressed!();

      expect(secondFired, isTrue,
          reason: 'a stale closure would act on a stale screen state');
      expect(firstFired, isFalse);
    });
  });

  group('real changes do notify', () {
    test('a different label notifies', () {
      controller.setFor(kSectionFlash, [_action('Refresh')]);
      final n = _Counter(controller);

      controller.setFor(kSectionFlash, [_action('Reload')]);

      expect(n.count, 1);
    });

    test('becoming disabled notifies', () {
      controller.setFor(kSectionFlash, [_action('Refresh')]);
      final n = _Counter(controller);

      controller.setFor(kSectionFlash, [_action('Refresh', enabled: false)]);

      expect(n.count, 1, reason: 'the entry has to dim when it disables');
    });

    test('starting to spin notifies', () {
      controller.setFor(kSectionFlash, [_action('Refresh')]);
      final n = _Counter(controller);

      controller.setFor(kSectionFlash, [_action('Refresh', busy: true)]);

      expect(n.count, 1,
          reason: 'busy swaps the glyph for the spinner, so it is a change');
    });

    test('a change to a section that is not on screen stays quiet', () {
      controller.setFor(kSectionFlash, [_action('Refresh')]);
      final n = _Counter(controller);

      controller.setFor(kSectionBookmarks, [_action('Mark all read')]);

      expect(n.count, 0,
          reason: 'nothing visible changed, so nothing needs redrawing');
    });

    test('the newest registration is the one that sticks', () {
      // Frame-level coalescing belongs to the scheduler and is bypassed by
      // the synchronous test path; what matters here is that a later set
      // replaces an earlier one rather than being dropped.
      controller.setFor(kSectionFlash, [_action('A')]);
      controller.setFor(kSectionFlash, [_action('B')]);
      controller.setFor(kSectionFlash, [_action('C')]);

      expect(controller.actions.single.label, 'C');
    });
  });

  group('selecting a section', () {
    test('selecting the section already selected does not notify', () {
      controller.setFor(kSectionFlash, [_action('Refresh')]);
      final n = _Counter(controller);

      controller.selectSection(kSectionFlash);

      expect(n.count, 0);
    });

    test('selecting a different section notifies', () {
      final n = _Counter(controller);
      controller.selectSection(kSectionAlerts);
      expect(n.count, 1);
    });
  });
}

/// Counts notifications from the moment it is created.
class _Counter {
  int count = 0;
  _Counter(ChangeNotifier notifier) {
    notifier.addListener(_bump);
    addTearDown(() => notifier.removeListener(_bump));
  }
  void _bump() => count++;
}

