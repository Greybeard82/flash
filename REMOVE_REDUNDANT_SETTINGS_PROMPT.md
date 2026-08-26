# Task for Claude Code

<context>
This is the "flash" Flutter app. The Settings screen (`lib/screens/settings_screen.dart`) has accumulated controls that now duplicate faster main-screen equivalents reachable from the FAB cluster in `lib/screens/feed_screen.dart` via `showBubblePanel` (`lib/widgets/bubble_panel.dart`). The duplicates are unused dead weight and must be deleted outright — not commented out, not feature-flagged, not left as unreachable code. Where a feature is being *relocated* rather than deleted (item 3), the underlying preference/logic stays; only its Settings-screen UI moves.

I have already scoped this precisely by reading the code. Trust the file/line references below as a starting point, but re-read each file yourself before editing — line numbers shift as you make earlier edits in the same file.
</context>

<task_1_changelog>
Delete the Changelog section from Settings entirely. It has no separate screen/route — it's built inline.

- `lib/screens/settings_screen.dart`: delete the `// ── Changelog ──` comment, `_sectionHeader(l10n.changelog)` call, and `_buildChangelog()` call (currently lines 479–481), plus the `_buildChangelog()` method definition itself (currently lines 701–769, ends before `_cleanupAgeControl`/whatever method follows it — verify the exact closing brace).
- Remove the `changelog` l10n key and its string from every `lib/l10n/app_*.arb` file, then regenerate localizations (check `l10n.yaml` / `pubspec.yaml` for the generation command — typically `flutter gen-l10n`). Do not hand-edit the generated `app_localizations*.dart` files directly; regenerate them.
- Grep the whole `lib/` and `test/` trees for `changelog` and `Changelog` (case-insensitive) after deleting to confirm nothing references it anymore.
</task_1_changelog>

<task_2_theme_and_newspaper>
Delete the Theme selector and Newspaper mode toggle from Settings. Both already exist and fully work in `QuickSettingsBubble` (`lib/widgets/quick_settings_bubble.dart`), which writes the same DB keys (`theme`, `newspaper_mode`) through `SettingsRepository`. Do not touch `QuickSettingsBubble` — it is the surviving implementation.

- `lib/screens/settings_screen.dart`: delete the `_themeSelector(s, l10n)` and `_newspaperToggle(s, l10n)` calls (currently lines 321–322, inside the "Reading" section — **do not remove the `_sectionHeader(l10n.reading)` header or any of the other Reading-section rows**: `markReadOnScroll` moves per task 3 below, but `autoMarkReadAtBottom` and its delay dropdown, currently lines 329–354, must stay untouched in Settings).
- Delete the `_themeSelector` method (currently lines 623–671) and `_newspaperToggle` method (currently lines 673–684) definitions.
- `lib/app.dart` has a comment (currently lines 83–87) noting Theme/Newspaper mode can be changed outside Settings via the Quick Settings bubble — update or trim it if it now reads oddly once the Settings copy is gone (it was written anticipating this).
- Check `test/theme_mode_test.dart`, `test/theme_persistence_test.dart`, `test/newspaper_mode_test.dart`: if a test exercises `SettingsScreen`'s theme/newspaper UI specifically, delete or rewrite it against `QuickSettingsBubble` instead; if a test exercises `AppSettings`/`SettingsRepository`/`app.dart` directly (not the Settings screen widget), leave it alone.
- Grep `lib/` for any other reference to `_themeSelector`/`_newspaperToggle` before deleting, in case something outside `settings_screen.dart` calls them (unlikely, but verify).
</task_2_theme_and_newspaper>

<task_3_mark_read_on_scroll>
This one is a **relocation, not a deletion**. The underlying preference (`mark_read_on_scroll` DB key, `AppSettings.markReadOnScroll` model field, and the scroll-handling logic in `feed_screen.dart`'s `_onScroll()`) must be preserved exactly as-is. Only the Settings-screen toggle UI moves to the Quick Settings bubble on the main screen.

- `lib/screens/settings_screen.dart`: delete the `_toggle(title: l10n.markReadOnScroll, ...)` block (currently lines 323–328).
- `lib/widgets/quick_settings_bubble.dart`: add a new `SwitchListTile` for "mark as read on scroll", following the exact pattern already used there for Newspaper mode:
  - Add a `bool _markReadOnScroll` state field, initialized in `initState()` from `widget.initial.markReadOnScroll`.
  - Add a `_setMarkReadOnScroll(bool value)` method mirroring `_setNewspaper`: `setState`, `await _repo.set('mark_read_on_scroll', value.toString())`, then `SettingsNotifier.instance.settingsChanged()`. No `onChanged` callback parameter is needed on the widget — `feed_screen.dart` already re-applies settings via `_applyReadingSettings` whenever `SettingsNotifier` fires (see its call sites at lines 174, 282, 385), so simply notifying is sufficient; do not add plumbing that already exists.
  - Add the `SwitchListTile` itself to the `build()` method's `Column`, below the existing Newspaper mode `SwitchListTile` (currently lines 121–130). Reuse `l10n.markReadOnScroll` and `l10n.markReadOnScrollSubtitle` (already defined, currently used at the deleted Settings call site) for the title/subtitle — do not invent new l10n strings.
- Leave `lib/models/settings.dart` (`markReadOnScroll` field), `lib/db/schema.dart` (line 130 default), and `feed_screen.dart`'s `_onScroll()` gate (line 536) untouched — none of that is being removed.
- Check `test/feed_behavior_test.dart` and `test/auto_mark_read_settings_test.dart` for any test that drives this toggle through the Settings screen widget specifically; if one exists, move it to test `QuickSettingsBubble` instead. Tests that only exercise the model/DB/scroll-handler logic need no change.
</task_3_mark_read_on_scroll>

<task_4_storage_section>
Delete the "Storage" section from Settings (cleanup-age stepper + max-articles-per-feed dropdown). Both controls write the same `cleanup_age_days` and `article_limit` keys that `FilterBubble` (`lib/widgets/filter_bubble.dart`) already edits via sliders — `FilterBubble`'s own doc comment (lines 16–33) already describes itself as the duplicate-in-waiting for this section. Do not touch `FilterBubble` — it is the surviving implementation.

- `lib/screens/settings_screen.dart`: delete the `// ── Storage ──` comment, `_sectionHeader(l10n.storage)` call, `_cleanupAgeControl(s)` call, and the `maxArticlesPerFeed` dropdown block (currently lines 377–405 as a whole, including the comment at lines 383–388 explaining the dropdown's extra-entry workaround — that workaround only existed because this dropdown coexisted with the Filter bubble's slider, so it goes too).
- Delete the `_cleanupAgeControl` method definition (currently lines 771–803).
- Remove the `storage` and `maxArticlesPerFeed` l10n keys from the `.arb` files **only if** they are not referenced anywhere else — grep first, since `l10n.articlesCount`, `l10n.articles50/100/200/500`, and `l10n.unlimited` may be shared with `FilterBubble`'s own labels (check before deleting any of those specifically).
- **Known behavior change to flag to me, not silently resolve**: Settings currently allows `cleanup_age_days` 5–20 and `article_limit` presets up to 500 or unlimited. `FilterBubble`'s sliders only go up to 15 days and 150 articles, with no "unlimited" option. After this removal, unlimited/500/16–20-day values become unreachable from the UI (existing stored values beyond the slider range would still load fine, just not be re-settable to those values from the UI). Don't silently widen the sliders to compensate — just leave a one-line note in your final summary so I can decide separately whether to extend `FilterBubble`'s ranges later.
</task_4_storage_section>

<forbidden_actions>
- Do not modify `QuickSettingsBubble`'s theme/newspaper logic beyond adding the new mark-read-on-scroll toggle in task 3.
- Do not modify `FilterBubble` at all.
- Do not touch the `mark_read_on_scroll` DB default, model field, or `_onScroll()` logic — that behavior is not being removed.
- Do not add new l10n strings; reuse the existing `markReadOnScroll`/`markReadOnScrollSubtitle` keys.
- Do not add abstractions, helper widgets, or refactor code beyond what's needed to complete these four removals/relocations.
- Do not hand-edit generated localization files — regenerate them from the `.arb` sources.
- Do not delete an l10n key without first grepping for other usages.
</forbidden_actions>

<stop_conditions>
Stop and ask me before:
- Deleting any `.arb` key you're not fully certain is unused elsewhere.
- Touching any file not named in this prompt.
- Changing anything about `FilterBubble`'s slider ranges.
</stop_conditions>

<verification>
After all four tasks:
1. `flutter analyze` — zero new warnings/errors.
2. `flutter test` — full suite passes.
3. Grep `lib/` and `test/` for: `changelog`, `_buildChangelog`, `_themeSelector`, `_newspaperToggle`, `_cleanupAgeControl`, `maxArticlesPerFeed` (post-arb-cleanup check) — confirm each is either gone or, if a match remains, that it's legitimately unrelated.
4. Run the app, open Settings, and confirm: no Changelog section, no Theme/Newspaper controls, no Storage section, and the Reading section still shows Mark-read-on-scroll... wait, no — confirm Mark-read-on-scroll is **gone** from Settings. Then open the Quick Settings bubble from the main screen FAB cluster and confirm Theme, Newspaper mode, and the new Mark-read-on-scroll toggle all appear and persist correctly across app restart.
5. Report a short summary: what was deleted, what was moved, and the Storage/FilterBubble range-mismatch note from task 4.
</verification>

Only make changes directly requested above. Do not add features, refactors, or cleanup beyond what's specified.
