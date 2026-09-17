import 'package:flutter/painting.dart' show Color;

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

/// The tint Android applies to the small icon in the shade.
///
/// **One constant, not a theme pair.** `Notification.color` is a single
/// ARGB read in the system's process, long after any Flutter theme has
/// stopped existing, so there is nothing to resolve a light/dark pair
/// against. `primary` light measures 2.7:1 on a dark shade and dark 1.8:1
/// on a light one, which is why neither palette value could be reused and a
/// third had to be authored.
///
/// Measured here rather than taken on trust, and it agrees with 1.3 to the
/// digit: **4.35:1** on `#FFFFFF`, **3.96:1** on `#1B1B1B`, **3.69:1** on
/// the `#1F2223` shade card.
///
/// **Do not re-derive `#12787F`.** It measures 5.23 / 3.30 / **3.06**, and
/// a 0.07 margin against a surface nobody controls — OEM skins, One UI
/// and Material You each draw the shade card differently — is not a
/// margin. Neither value is a palette token, so there was never a fidelity
/// case for the riskier one.
///
/// Tints the small icon only. On API 30 and earlier it also tinted the
/// shade's app-name label at ~12sp, where the bar is 4.5:1 — see 5.1:
/// the answer is that old shades get a slightly quiet app name, not that
/// this value changes.
const Color kFlashNotificationAccent = Color(0xFF15868E);
