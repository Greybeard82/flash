import 'package:flutter/widgets.dart';

/// Section indices, matching the order of the nav destinations.
const int kSectionFlash = 0;
const int kSectionCategories = 1;
const int kSectionBookmarks = 2;
const int kSectionAlerts = 3;

/// One action a section offers — what used to be a floating action button.
///
/// [onPressed] being null means shown-but-disabled, which is how Flash's
/// refresh behaves while a refresh is already running. [busy] is separate
/// from that: it says the icon should be the spinner rather than the glyph,
/// and it is part of the value so a refresh starting or finishing is a real
/// change rather than something the shell has to be told about twice.
@immutable
class SectionAction {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const SectionAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  /// Deliberately ignores [onPressed]'s identity.
  ///
  /// Screens rebuild these in `build`, so the closure is a new object every
  /// frame and comparing it would make every frame look like a change — the
  /// controller would notify, the shell would rebuild, and round it goes.
  /// What matters is whether the action *looks or behaves* different:
  /// same icon, same label, same enabled-ness, same busy-ness.
  bool sameShapeAs(SectionAction other) =>
      icon == other.icon &&
      label == other.label &&
      busy == other.busy &&
      (onPressed == null) == (other.onPressed == null);
}

/// The actions belonging to whichever section is currently on screen.
///
/// On a phone each screen still draws its own floating action button. In the
/// rail layouts there is one sidebar for all four sections, so the actions
/// have to live somewhere both the rail and the screens can reach — here.
///
/// Keyed by section rather than "last writer wins": all four screens sit in
/// a kept-alive IndexedStack and therefore all four build, so a single slot
/// would end up holding whichever of them rebuilt most recently rather than
/// the one being looked at.
class SectionActionsController extends ChangeNotifier {
  static final SectionActionsController instance =
      SectionActionsController._();

  SectionActionsController._();

  final Map<int, List<SectionAction>> _bySection = {};
  int _current = kSectionFlash;

  /// The actions for the section on screen. Empty until that section has
  /// registered any, which is the correct thing to show in the meantime.
  List<SectionAction> get actions => _bySection[_current] ?? const [];

  /// Called by a screen with its own current actions. Safe to call from
  /// `build`: the notification is deferred to after the frame, and only
  /// happens when something actually changed.
  void setFor(int section, List<SectionAction> actions) {
    final existing = _bySection[section];
    final changed = existing == null ||
        existing.length != actions.length ||
        !List.generate(actions.length, (i) => actions[i].sameShapeAs(existing[i]))
            .every((same) => same);

    // Store regardless, so the freshest closures are the ones that fire even
    // when nothing about the shape changed.
    _bySection[section] = actions;
    if (changed && section == _current) _notifyAfterFrame();
  }

  /// Called by the shell when the selected section changes.
  void selectSection(int section) {
    if (_current == section) return;
    _current = section;
    _notifyAfterFrame();
  }

  bool _notificationPending = false;

  /// Test-only: notify synchronously instead of after the frame.
  ///
  /// The deferral below needs a running frame pipeline to land, which a unit
  /// test does not have. Rather than make every test drive frames — and test
  /// the scheduler instead of this class — tests flip this and assert on the
  /// notifications directly.
  @visibleForTesting
  static bool notifyImmediatelyForTesting = false;

  /// Notifying inside `build` throws; screens register from `build`, so every
  /// notification goes out after the frame that caused it. Coalesced, since
  /// four screens registering in one frame is one change to the sidebar.
  void _notifyAfterFrame() {
    if (notifyImmediatelyForTesting) {
      notifyListeners();
      return;
    }
    if (_notificationPending) return;
    _notificationPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationPending = false;
      notifyListeners();
    });
  }

  /// Test-only reset.
  @visibleForTesting
  void resetForTesting() {
    _bySection.clear();
    _current = kSectionFlash;
    _notificationPending = false;
  }
}

/// Marks a subtree as living inside a rail-based shell, where a screen's
/// actions belong in the sidebar rather than in its own corner.
///
/// One mechanism for all four screens, rather than each checking width for
/// itself: the shell already knows which layout it chose, and a screen
/// asking the same question independently is a second answer that can
/// disagree with the first.
class SectionActionsHost extends InheritedWidget {
  const SectionActionsHost({super.key, required super.child});

  /// True when the sidebar is going to render this screen's actions.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SectionActionsHost>() != null;

  @override
  bool updateShouldNotify(SectionActionsHost oldWidget) => false;
}
