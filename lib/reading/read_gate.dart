/// The single decision point in front of every scroll-driven `is_read = 1`
/// write.
///
/// A `ScrollController` listener cannot tell you *why* the offset changed. It
/// fires identically for a finger drag, a `jumpTo`, and a layout pass that
/// grew a row above the viewport — and the mark-as-read walk then treats all
/// three as "the user scrolled past these". Pass 10 measured `maxScrollExtent`
/// growing by ~740px in the middle of a single drag as thumbnails resolved, so
/// the layout-induced case is not hypothetical.
///
/// Four conditions, all of which must hold. They are deliberately independent:
/// each one blocks on its own, so a future caller that forgets to compute one
/// of them fails closed rather than open.
///
/// Pure Dart by design — no Flutter import beyond `Duration`. This is the
/// safety property the pass exists to guarantee, so it is unit-testable on its
/// own rather than buried in a private method on a 1500-line State.
class ReadGateInput {
  /// True only when the offset change came from a real drag or its ballistic
  /// continuation.
  ///
  /// Derived from `UserScrollNotification` / `ScrollStartNotification
  /// .dragDetails`, never from comparing offsets — a `jumpTo` produces exactly
  /// the same offset delta a drag would. Programmatic scrolls, retirement
  /// compensation and layout corrections all set this false.
  final bool userInitiated;

  /// False while any built row's extent is still expected to change.
  ///
  /// A row whose thumbnail has not resolved is shorter than it will be, so the
  /// cumulative-height walk puts the viewport top at the wrong article and
  /// marks the wrong set read.
  final bool extentsStable;

  /// Time since the app last reached `AppLifecycleState.resumed`.
  ///
  /// Restoration, re-layout and the first post-resume frames all land in this
  /// window. Nothing in it is a user reading anything.
  final Duration sinceResume;

  /// The existing condition: the article's midpoint has passed the viewport
  /// top. Unchanged by this pass.
  final bool pastMidpoint;

  /// How long after a resume to keep the gate shut. Exclusive — see
  /// [ReadGate.allows].
  final Duration resumeGrace;

  const ReadGateInput({
    required this.userInitiated,
    required this.extentsStable,
    required this.sinceResume,
    required this.pastMidpoint,
    required this.resumeGrace,
  });
}

/// Default grace after a resume before scroll-driven reads are allowed again.
///
/// Long enough to cover restoration and the re-layout that follows it, short
/// enough that a user who resumes and immediately scrolls does not notice the
/// first flick failing to mark anything. Named rather than a literal at the
/// call site so there is one place to change it.
const Duration kResumeReadGrace = Duration(milliseconds: 600);

abstract final class ReadGate {
  /// Whether a scroll-driven read may be written.
  ///
  /// The resume boundary is **exclusive**: at exactly [ReadGateInput
  /// .resumeGrace] the gate is still shut. A boundary has to fall on one side
  /// or the other, and shut is the side that cannot corrupt data.
  static bool allows(ReadGateInput input) {
    if (!input.userInitiated) return false;
    if (!input.extentsStable) return false;
    if (!input.pastMidpoint) return false;
    if (input.sinceResume <= input.resumeGrace) return false;
    return true;
  }
}
