/// The group every Flash notification belongs to.
///
/// Android stacks notifications from the same app only when they agree on a
/// group. Flash posts two kinds — keyword alerts and the unread count — and
/// the count carried no group at all, so several keyword alerts would collapse
/// together while the count sat outside as a loose card.
///
/// One key for both, app-level rather than per-kind, so anything Flash adds
/// later is grouped by default rather than by remembering to.
///
/// **These two will still not stack with each other, and this key is not what
/// stops them.** Android splits the shade into an alerting section and a
/// Silent one and never groups across that line. Keyword alerts sit on a
/// channel at importance 3; the unread count sits on one at importance 2,
/// which is what puts it under Silent — deliberately, because a heads-up for
/// "you still have unread articles" would be intolerable. Verified on device:
/// with both carrying this key they still render in separate sections, and a
/// group summary would not change that, because the split is by section and
/// not by grouping. Moving the count up to importance 3 is the only thing
/// that would merge them, and that trade is not worth making.
///
/// (Worth knowing if you try: an existing channel's importance cannot be
/// raised in code. Android hands channel settings to the user once the
/// channel exists, so changing the value here does nothing on a device that
/// has already run the app — it takes a new channel id, or a reinstall.)
///
/// What the key does earn: several keyword alerts collapse under one heading
/// instead of stacking up as separate cards, which is what it is for.
const String kFlashNotificationGroupKey = 'io.getflash.app.notifications';
