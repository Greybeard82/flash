# Context7 dependency and API audit — 17 September 2026

Branch `main` at `2772b49`, version 0.9.9+34, Quiet Ink merged. Read-only pass:
no app code was changed, nothing was built, no device was touched.

## For David

**One to fix before production, eight worth doing after, ten to leave alone.**

The one: the launcher-badge library is three releases behind, and one of those
fixed a bug where updating the badge fires a notification several times over.
Flash does that on every unread-count change, so if it bites, 25 testers see
duplicates. One-line version bump, no code change. Unreproduced — the evidence
is the library's own release note, not something I saw happen.

Nothing else is broken: the analyzer is clean, the app targets exactly the Android
level Play requires for 30 September, the cloud model it calls is supported into
mid-2027, and the old Java library in the build has no known vulnerabilities.

Two decisions are yours, neither a code change. The Gemini gateway began enforcing
its security check automatically in July — I cannot see the console, so please
confirm that setup or every tester's cloud summaries fail. And the on-device
summary rests on a library Google still marks beta; you are on the first of four.

---

# The record

## Step 0 — Context7 availability

Context7 MCP tools were present and used. Tool names as exposed in this session:

- `mcp__claude_ai_Context7__resolve-library-id`
- `mcp__claude_ai_Context7__query-docs`

**11 Context7 calls total** — 3 `resolve-library-id`, 8 `query-docs`.

Libraries resolved and queried:

| Library ID | Calls | Used for |
|---|---|---|
| `/websites/pub_dev_firebase_ai` | 1 | `generativeModel` signature and model-string validation behaviour |
| `/websites/firebase_google_ai-logic` | 3 | supported model names, App Check integration, production checklist |
| `/pichillilorenzo/inappwebview.dev` | 1 | `shouldInterceptRequest` / `useShouldInterceptRequest` semantics |
| `/websites/inappwebview_dev` | 1 | `mixedContentMode` default |
| `/websites/developers_google_ml-kit` | 2 | GenAI Prompt API surface, release notes, known issues |

**Prompt-injection check:** no fetched documentation contained text addressed to
me or attempting to direct my behaviour. All doc content was treated as data.

## Step 1 — Toolchain snapshot

| Item | Value | Latest available | Source |
|---|---|---|---|
| Flutter | 3.41.6 stable (rev `db50e20168`, 2026-03-25) | — | `flutter --version` |
| Dart | 3.11.4 stable | — | `dart --version` |
| `flutter analyze` | **No issues found** (9.7s) | — | `flutter analyze` |
| AGP | 8.11.1 | 8.13.2 | `settings.gradle.kts:15`, Google Maven |
| Kotlin | 2.2.20 | current | `settings.gradle.kts:19` |
| Gradle wrapper | 8.14 | — | `gradle-wrapper.properties` |
| google-services | 4.4.4 | 4.5.0 | `settings.gradle.kts:17`, Google Maven |
| compileSdk / targetSdk / minSdk | 36 / 36 / 24 | — | `android/app/build.gradle.kts:70,105,110` |
| Java / jvmTarget | 17 | — | `android/app/build.gradle.kts:73-80` |
| `desugar_jdk_libs` | 2.1.4 | 2.1.5 | `android/app/build.gradle.kts:159`, Google Maven |
| `com.google.mlkit:genai-prompt` | **1.0.0-beta1** | **1.0.0-beta4** | `android/app/build.gradle.kts:161`, Google Maven metadata |
| Database schema | v19 | — | `lib/db/database.dart:45` |
| Dart source | 117 files, 30,173 lines | — | — |
| Test suite | 136 `*_test.dart` files | — | — |

`flutter analyze` produced **zero** deprecation warnings and zero infos. There is
nothing in this audit that came from the analyzer, because it had nothing to say.

## Step 1 — `flutter pub outdated` (full)

`pubspec.lock` was not modified by this pass; `git status --porcelain pubspec.lock`
is empty and `git diff pubspec.lock` is empty.

```
Package Name                                    Current               Upgradable            Resolvable            Latest

direct dependencies:
app_badge_plus                                  *1.2.9                1.3.5                 1.3.5                 1.3.5
cached_network_image                            *3.4.0                *3.4.1                *3.4.1                4.0.0
file_picker                                     *8.3.7                *8.3.7                13.1.0                13.1.0
firebase_app_check                              *0.4.7                0.4.8                 0.4.8                 0.4.8
firebase_core                                   *4.14.0               4.15.0                4.15.0                4.15.0
flutter_inappwebview                            *6.0.0                6.1.5                 6.1.5                 6.1.5
flutter_local_notifications                     *18.0.1               *18.0.1               22.3.1                22.3.1
flutter_svg                                     *2.2.4                2.3.0                 2.3.0                 2.3.0
home_widget                                     *0.9.4                *0.9.4                0.10.0                0.10.0
html                                            *0.15.6               0.15.7                0.15.7                0.15.7
intl                                            *0.20.2 (overridden)  *0.20.3 (overridden)  *0.20.3 (overridden)  0.20.3
path_provider                                   *2.1.5                2.1.6                 2.1.6                 2.1.6
share_plus                                      *12.0.2               *12.0.2               13.3.0                13.3.0
shimmer                                         *3.0.0                *3.0.0                *3.0.0                4.0.0
sqflite                                         *2.4.2                *2.4.2+1              *2.4.2+1              2.4.4
workmanager                                     *0.9.0+3              *0.9.3                0.10.10               0.10.10
xml                                             *6.6.1                *6.6.1                *6.6.1                7.0.1

dev_dependencies:
flutter_lints                                   *4.0.0                *4.0.0                6.0.0                 6.0.0
sqflite_common_ffi                              *2.4.0+3              *2.4.0+3              *2.4.0+3              2.4.3

transitive dependencies:
android_file_picker                             -                     -                     2.0.0                 2.0.0
cached_network_image_platform_interface         *4.1.1                *4.1.1                *4.1.1                5.0.0
cached_network_image_web                        *1.3.0                *1.3.1                *1.3.1                2.0.0
clock                                           *1.1.2                *1.1.2                *1.1.2                1.1.3
code_assets                                     *1.0.0                *1.2.1                *1.2.1                2.1.0
cross_file                                      *0.3.5+2              0.3.5+5               0.3.5+5               0.3.5+5
dbus                                            *0.7.12               *0.7.15               *0.7.15               0.8.0
ffi_leak_tracker                                -                     -                     0.1.2                 0.1.2
file_picker_darwin                              -                     -                     2.1.0                 2.1.0
file_picker_linux                               -                     -                     2.0.0                 2.0.0
file_picker_platform_interface                  -                     -                     4.0.0                 4.0.0
file_picker_web                                 -                     -                     4.0.0                 4.0.0
firebase_auth                                   *6.6.1                6.7.0                 6.7.0                 6.7.0
firebase_auth_platform_interface                *9.0.7                9.1.0                 9.1.0                 9.1.0
firebase_auth_web                               *6.2.7                6.3.0                 6.3.0                 6.3.0
firebase_core_web                               *3.11.0               3.12.0                3.12.0                3.12.0
flutter_cache_manager                           *3.4.1                3.4.3                 3.4.3                 3.4.3
flutter_inappwebview_web                        *1.0.8                1.1.2                 1.1.2                 1.1.2
flutter_inappwebview_windows                    -                     0.6.0                 0.6.0                 0.6.0
flutter_local_notifications_linux               *5.0.0                *5.0.0                8.0.1                 8.0.1
flutter_local_notifications_platform_interface  *8.0.0                *8.0.0                12.2.0                12.2.0
flutter_local_notifications_web                 -                     -                     1.0.0                 1.0.0
flutter_local_notifications_windows             -                     -                     3.1.1                 3.1.1
flutter_plugin_android_lifecycle                *2.0.34               2.0.35                -                     2.0.35
glob                                            *2.1.3                2.2.0                 2.2.0                 2.2.0
hooks                                           *1.0.2                *2.0.2                *2.0.2                2.2.0
jni                                             -                     1.0.3                 1.0.3                 1.0.3
jni_flutter                                     -                     1.0.3                 1.0.3                 1.0.3
jni_util                                        -                     1.0.0                 1.0.0                 1.0.0
js                                              *0.6.7                -                     -                     0.7.2    (discontinued)
material_color_utilities                        *0.13.0               *0.13.0               *0.13.0               0.13.1
meta                                            *1.17.0               *1.17.0               *1.17.0               1.19.0
mime                                            *1.0.6                2.1.0                 2.1.0                 2.1.0
native_toolchain_c                              *0.17.6               *0.19.2               *0.19.2               0.19.5
objective_c                                     *9.3.0                *9.5.0                *9.5.0                9.6.0
package_config                                  -                     3.0.0                 3.0.0                 3.0.0
path_provider_android                           *2.2.23               2.3.1                 2.3.1                 2.3.1
path_provider_linux                             *2.2.1                2.2.2                 2.2.2                 2.2.2
path_provider_platform_interface                *2.1.2                2.1.3                 2.1.3                 2.1.3
platform                                        *3.1.6                *3.1.6                *3.1.6                3.2.0
pub_semver                                      *2.2.0                2.2.1                 2.2.1                 2.2.1
record_use                                      -                     *0.6.0                *0.6.0                1.1.1
share_plus_platform_interface                   *6.1.0                *6.1.0                7.2.0                 7.2.0
sqflite_android                                 *2.4.2+3              *2.4.2+3              *2.4.2+3              2.4.4
sqflite_common                                  *2.5.6                *2.5.8                *2.5.8                2.5.13
sqflite_darwin                                  *2.4.2                *2.4.2                *2.4.2                2.4.4
sqflite_platform_interface                      *2.4.0                *2.4.0                *2.4.0                2.4.2
synchronized                                    *3.4.0                *3.4.0+1              *3.4.0+1              3.4.2
timezone                                        *0.10.1               *0.10.1               0.11.1                0.11.1
url_launcher_android                            *6.3.29               *6.3.30               *6.3.30               6.3.33
url_launcher_ios                                *6.4.1                6.4.2                 6.4.2                 6.4.2
url_launcher_linux                              *3.2.2                3.2.3                 3.2.3                 3.2.3
url_launcher_macos                              *3.2.5                3.2.6                 3.2.6                 3.2.6
url_launcher_web                                *2.4.2                2.4.3                 2.4.3                 2.4.3
url_launcher_windows                            *3.1.5                3.1.6                 3.1.6                 3.1.6
uuid                                            *4.5.3                4.6.0                 4.6.0                 4.6.0
vector_graphics                                 *1.1.21               1.2.3                 1.2.3                 1.2.3
vector_graphics_compiler                        *1.2.0                1.3.0                 1.3.0                 1.3.0
vector_math                                     *2.2.0                *2.2.0                *2.2.0                2.4.2
win32                                           *5.15.0               *5.15.0               6.4.0                 6.4.0
windows_file_picker                             -                     -                     2.0.0                 2.0.0
workmanager_android                             *0.9.0+2              *0.9.3                0.10.9                0.10.9
workmanager_apple                               *0.9.1+2              *0.9.6                0.9.11                0.9.11
workmanager_linux                               -                     -                     0.1.1+1               0.1.1+1
workmanager_platform_interface                  *0.9.1+1              *0.9.4                0.10.5                0.10.5
workmanager_web                                 -                     -                     0.2.0                 0.2.0

transitive dev_dependencies:
archive                                         *4.0.9                4.3.0                 4.3.0                 4.3.0
cli_util                                        *0.4.2                *0.4.2                *0.4.2                0.6.0
image                                           *4.8.0                4.10.1                4.10.1                4.10.1
lints                                           *4.0.0                *4.0.0                6.1.0                 6.1.0
matcher                                         *0.12.19              *0.12.19              *0.12.19              0.12.20
posix                                           *6.5.0                6.5.2                 6.5.2                 6.5.2
sqlite3                                         *3.5.2                *3.5.2                *3.5.2                3.6.0
stack_trace                                     *1.12.1               *1.12.1               *1.12.1               1.12.2
test_api                                        *0.7.10               *0.7.10               *0.7.10               0.7.14
vm_service                                      *15.0.2               15.3.0                15.3.0                15.3.0

50 upgradable dependencies are locked (in pubspec.lock) to older versions.
15 dependencies are constrained to versions that are older than a resolvable version.
js — package has been discontinued.
```

`firebase_ai` does not appear: 4.0.0 is both current and latest.

---

## Bucket A — before production

### A1. The launcher-badge library carries a duplicate-notification bug that Flash's hottest write path triggers

**Where:** `lib/services/unread_badge_service.dart:205` — `await AppBadgePlus.updateBadge(badge)`.
Driven from eight call sites: `lib/screens/feed_screen.dart:772, 832, 1295, 1344, 1426, 1430, 1482, 1483`.

**Evidence** (source: `changelog`, pub.dev `app_badge_plus`):

> **1.3.4** — "Notification will be triggered multiple times when updateBadge" was resolved.

Flash resolves `app_badge_plus` **1.2.9** (source: `pub outdated`), which predates
that fix. Two further Android fixes also sit in the gap:

> **1.3.5** — "remove trailing space in Honor CHANGE_BADGE permission name"
> **1.3.3** — "POCO / HyperOS (`com.mi.android.globallauncher`) numeric badge count (no `extraNotification` API)"

This lands on top of a path that has already produced a real defect in this area —
`unread_badge_service.dart:198-204` records a stranded unread-count notification
caused by a badge broadcast failing, with the note *"A Samsung launcher is exactly
the kind to answer a badge broadcast oddly."*

**Change:** bump the lockfile entry for `app_badge_plus` to 1.3.5. **No pubspec
edit is needed** — the existing constraint `^1.1.0` (`pubspec.yaml:60`) already
admits it, and `pub outdated` lists 1.3.5 as both upgradable and resolvable.
1.3.0 raised the floor to Flutter 3.32.0 / Dart 3.8.0; Flash is on 3.41.6 / 3.11.4.

**Blast radius:** one line in `pubspec.lock`, zero Dart changes. Five existing
tests cover this surface (`badge_accuracy_test.dart`, `badge_suppression_test.dart`,
`unread_badge_service_test.dart`, `unread_badge_mark_all_read_test.dart`,
`alert_badges_test.dart`). **Needs on-device verification** on the Samsung M51 —
mark-all-read and a refresh that changes the unread count, watching the shade for
duplicates. Read-only observation only; no device state changes.

**Standing cautions touched:** article retirement / read state — the badge total
is derived from unread counts, so a regression here reads as a read-state bug.
Not orientation, not Impeller, not scroll offset, not font subsetting.

**How this could be wrong:** the release note does not say which launchers or
Android versions the duplicate notification affects. Some OEMs implement badges
by posting a notification and some do not; if the Pixel 11 Pro, Galaxy M51 and
Lenovo Tab M11 all use launchers on the non-notification path, this bug never
fires for Flash and the bump changes nothing. I have not reproduced it — the
evidence is a changelog line, not an observation.

---

## Bucket B — after launch, worth doing

### B1. Upgrading the notifications library deletes a block of hand-vendored build rules

**Where:** `pubspec.yaml:31` (`flutter_local_notifications: ^18.0.0`);
`android/app/proguard-rules.pro:22-70`; call sites `lib/main.dart:54`,
`lib/services/refresh_service.dart:71, 185, 262`.

**Evidence** (source: `changelog`, pub.dev `flutter_local_notifications`, plus the
repo's own note at `proguard-rules.pro:66`):

The proguard file says the Gson block *"becomes unnecessary at
flutter_local_notifications 19.0.0, which bumps Gson to 2.12 so the rules arrive
on their own"*, and defers it because 19.0.0 needs *"Flutter >= 3.22, Dart >= 3.4,
minSdk 21, Java 11"*. **Every one of those is now satisfied**: Flutter 3.41.6,
Dart 3.11.4, minSdk 24, Java 17. The note is simply out of date.

Going further to 22.3.1 is also in reach. The only requirement that moved since
is 21.0.0's floor:

> **21.0.0** — Flutter SDK 3.38.1, Dart SDK 3.10.0, Android API 24, Android compileSdk 36

Flash is at 3.41.6 / 3.11.4 / 24 / 36 — all met. The real cost is one API change:

> **20.0.0** — converted positional parameters to named parameters in `initialize()`, `show()`, `periodicallyShow()`, `cancel()`, `zonedSchedule()`

And one manifest note that does **not** affect Flash:

> **16.0.0** — plugin now declares only the bare minimum in `AndroidManifest.xml`; applications requiring scheduled notifications, full-screen intents, or actions must declare these themselves

Flash uses only `show()`, never `zonedSchedule()`, and already declares
`POST_NOTIFICATIONS` itself (`AndroidManifest.xml:5`).

**Change:** raise the constraint to `^22.3.1`, convert the four positional call
sites to named parameters, and delete `proguard-rules.pro:22-70` along with the
`-keepattributes`/`-keep` pair it explains.

**Blast radius:** 2 Dart files, 1 proguard file, 1 pubspec line. **Needs on-device
verification, and specifically the cancel path** — the Gson bug those rules exist
for manifested as `plugin.cancel()` throwing in release builds, so the unread-count
notification could never be dismissed. A debug build will not reproduce it; this
has to be a release APK.

**Standing cautions touched:** article retirement / read state (the unread-count
notification is driven by it). None of the others.

### B2. The share library has an Android main-thread I/O fix that Flash does not have

**Where:** `lib/services/share_service.dart:11, 28`; `pubspec.yaml:51`.

**Evidence** (source: `changelog`, pub.dev `share_plus`):

> **13.3.0** — "Do not do I/O operations on the main thread on Android."
> **13.0.0** — "Minimum Flutter version is 3.41.6", "Minimum Dart version is 3.11.0"

Flash is on Flutter **exactly 3.41.6** and Dart 3.11.4, so 13.3.0 is reachable.
There are **no breaking changes** to `SharePlus.instance.share(ShareParams(...))`
across 12.0.2 → 13.3.0, which is the only form Flash uses.

**Change:** `share_plus: ^13.3.0` in `pubspec.yaml`. No Dart change.

**Blast radius:** one pubspec line. Worth a manual share from an article and from
the summary sheet. ANR risk in Flash is low — it shares a URL and a title, not a
file — so this is hygiene rather than a fix for a symptom anyone has seen.

**Standing cautions touched:** none.

### B3. The on-device summary feature is three betas behind on a beta artifact

**Where:** `android/app/build.gradle.kts:161` — `com.google.mlkit:genai-prompt:1.0.0-beta1`.
Consumed at `GeminiNanoPlugin.kt:56` (`Generation.getClient()`), `:63` (`checkStatus()`),
`:105` (`generateContentStream()`).

**Evidence:**

- Google Maven `maven-metadata.xml` for `com.google.mlkit:genai-prompt` lists
  `<latest>` and `<release>` as **1.0.0-beta4**; published versions are
  alpha1, beta1, beta2, beta3, beta4. (source: Google Maven)
- (source: `Context7`, `/websites/developers_google_ml-kit`, known-issues page)
  > "The GenAI Prompt SDK version 1.0.0-beta3 throws an unhandled exception when calling checkStatus on non-Pixel devices. Users should upgrade to version 1.0.0-beta4 or later to resolve this."
- (source: `Context7`, same library, release notes)
  > "The July 21, 2026 release includes a specific update to the com.google.mlkit:genai-prompt artifact."

Flash is on beta1, so it is **not** exposed to the beta3 `checkStatus` bug, and
`checkAvailability()` wraps the call in try/catch and degrades to the cloud path
regardless (`GeminiNanoPlugin.kt:83-85`). The concern is currency, not a known
defect.

One thing to plan for: the current docs show model selection through a config
object —

> `val generativeModel = Generation.getClient(previewFastConfig)`

— whereas Flash calls the no-argument `Generation.getClient()`. Whether that
overload survives in beta4 can only be settled by compiling against it.

**Change:** bump to `1.0.0-beta4`, compile, and fix `getModel()` if the no-arg
overload is gone.

**Blast radius:** one gradle line, possibly `GeminiNanoPlugin.kt:55-58`. **Needs
on-device verification on the Pixel 11 Pro** — it is the only device that can run
Nano. Drive the summary sheet; read-only.

**Standing cautions touched:** none.

### B4. App Check replay protection is available and not switched on

**Where:** `lib/services/gemini_cloud_service.dart:114` — `FirebaseAI.googleAI()`.

**Evidence** (source: `Context7`, `/websites/firebase_google_ai-logic`, App Check page):

> ```dart
> final ai = await FirebaseAI.googleAI(
>   // For Flutter plugin v3.11.0 or lower (BoM v4.12.0 or lower), pass in App Check explicitly.
>   appCheck: FirebaseAppCheck.instance,
>   useLimitedUseAppCheckTokens: true,
> );
> ```

Two things follow, and they point opposite ways:

**Already correct, do not change:** Flash resolves `firebase_ai` **4.0.0**, which
is *above* 3.11.0, so App Check is wired automatically and the bare
`FirebaseAI.googleAI()` at line 114 is right. `main.dart:32-33` doing the
`activate()` is sufficient. The comment at `main.dart:29-31` is accurate.

**Worth adding:** `useLimitedUseAppCheckTokens: true` requests single-use tokens
instead of reusable ones, which is replay protection for the gateway call. Flash
does not pass it.

**Change:** `FirebaseAI.googleAI(useLimitedUseAppCheckTokens: true)`.

**Blast radius:** one line in one file. `gemini_cloud_service_test.dart` stubs the
chunk stream, so tests are unaffected. Should be verified on a device that already
has a working cloud summary, because limited-use tokens fail differently from
reusable ones if attestation is misconfigured.

**Standing cautions touched:** none.

### B5. The newer lint set costs nothing — measured, not guessed

**Where:** `pubspec.yaml:76` (`flutter_lints: ^4.0.0`), `analysis_options.yaml:9`.

**Evidence** (source: `changelog`, pub.dev `flutter_lints`):

> **6.0.0** adds `strict_top_level_inference`, `unnecessary_underscores`
> **5.0.0** adds `invalid_runtime_check_with_js_interop_types`, `unnecessary_library_name`; removes `avoid_null_checks_in_equality_operators`, `prefer_const_constructors`, `prefer_const_declarations`, `prefer_const_literals_to_create_immutables`

I measured the impact rather than estimating it: `lib/` and `test/` were copied to
a scratch directory outside the repo with an `analysis_options.yaml` enabling
exactly those four added rules, and `dart analyze` was run there. The repo was not
touched.

**Result: 0 findings.** (The run reported three `asset_directory_does_not_exist`
warnings, which are artefacts of the copy not carrying `assets/`, not lint hits.)

Since 5.0.0 also *removes* four rules, the bump can only reduce analyzer output.

**Change:** `flutter_lints: ^6.0.0`.

**Blast radius:** one pubspec line, zero source changes, no device needed.

**Standing cautions touched:** none.

### B6. The `intl` override is redundant and hides an exact pin

**Where:** `pubspec.yaml:65` (`intl: any`) and `pubspec.yaml:69-70`
(`dependency_overrides: intl: ^0.20.0`).

**Evidence** (source: `pub outdated` and the Flutter SDK):

`C:\Users\david\flutter\packages\flutter_localizations\pubspec.yaml` pins
`intl: 0.20.2` — an **exact** version, not a range. `pubspec.lock` resolves
`intl 0.20.2`. So the override changes nothing today.

What it does do is bypass that exact pin. `pub outdated` already shows intl
0.20.3 as upgradable *because of the override*; without it, resolution would be
locked to whatever `flutter_localizations` names. A future `flutter pub upgrade`
could therefore take intl 0.20.3 against a `flutter_localizations` that wants
0.20.2, and the override is precisely what would stop pub complaining. Flash's
only intl use is generated l10n code (`Intl.pluralLogic`, `Intl.canonicalizedLocale`,
8 imports under `lib/l10n/`), so the practical risk is small — but this is the
one dependency in the file with no explanatory comment, which suggests it is
vestigial rather than reasoned.

**Change:** delete the `dependency_overrides` block and set `intl: 0.20.2`.

**Blast radius:** two pubspec lines. `pubspec.lock` must be regenerated and
diffed; `arb_parity_test.dart` and the l10n tests cover the surface. No device.

**Standing cautions touched:** none.

### B7. Android toolchain is a little behind

**Where:** `android/settings.gradle.kts:15, 17`; `android/app/build.gradle.kts:159`.

**Evidence** (source: Google Maven `maven-metadata.xml`):

| Item | Flash | Latest |
|---|---|---|
| AGP | 8.11.1 | 8.13.2 |
| google-services | 4.4.4 | 4.5.0 |
| `desugar_jdk_libs` | 2.1.4 | 2.1.5 |
| Kotlin | 2.2.20 | current |

Nothing here is broken. One forward-looking note: `app_badge_plus` 1.3.1 added
*"Android build with AGP 9 when `android.builtInKotlin=false`"* and 1.3.0
*"Migrates to built-in Kotlin for AGP 9.0+ compatibility"* — so A1's bump also
buys AGP 9 readiness for when that lands.

**Change:** bump the three, one at a time, with a release build after each.

**Blast radius:** build only, no source. Must be a **release** build, because R8
full mode is where this project's build problems have historically shown up
(`proguard-rules.pro:44-49`). **Standing caution touched: font subsetting** — a
release build is also where tree-shaking and the Literata subset are exercised;
check the APK size does not move unexpectedly.

### B8. Confirm whether the cloud model name is a pinned version or an auto-updating alias

**Where:** `lib/services/gemini_cloud_service.dart:73` — `static const String _model = 'gemini-3.5-flash-lite';`

**Evidence** (source: `Context7` + live Firebase docs, `firebase.google.com/docs/ai-logic/models`):

The model string is **valid and well chosen** — see "Verified, no finding" below.
But the production checklist says (source: `Context7`, `/websites/firebase_google_ai-logic`):

> "In production, always use specific stable model versions rather than preview, experimental, or auto-updated aliases. Using stable versions prevents unexpected behavior or responses that can occur when underlying models are automatically updated."

The same docs show older models in a suffixed form (`gemini-2.0-flash-001`,
`gemini-2.0-flash-lite-001`) described as having *"their respective auto-updated
aliases"*, which implies the bare name is the alias and the `-001` form is the pin.
**I could not confirm from the docs I fetched whether a `-001` form exists for
`gemini-3.5-flash-lite`**, so I cannot say which of the two Flash is using.

**Change:** check the models page for a suffixed form; if one exists, pin it.

**Blast radius:** one constant. `gemini_cloud_service_test.dart` pins `modelId`.
Needs one device check that a summary still generates.

**Standing cautions touched:** none.

---

## Bucket C — not worth it

| Item | Current → Latest | Why not |
|---|---|---|
| `file_picker` | 8.3.7 → 13.1.0 | Four majors. 11.0.0 moved to static methods, 12.0.0 changed `pickFiles()` to return `Future<List<PlatformFile>>` and made `fileName`/`bytes` **required** on `saveFile()`, 13.0.0 removed `allowMultiple`, `withData`, `lockParentWindow`, `androidSafOptions`. Flash uses `FilePicker.platform.pickFiles` and `.saveFile` at four sites (`local_backup_service.dart:59,74`, `opml_service.dart:335,437`). Real rewrite, no fix Flash needs. (source: `changelog`) |
| `cached_network_image` | 3.4.0 → 4.0.0 | **Not reachable.** 4.0.0 "Requires Flutter `>=3.44.0` and Dart `^3.12.0`"; Flash is on 3.41.6 / 3.11.4. 3.4.1 is a Wasm/`js_interop` change only, with no Android or caching fix. Hence `pub outdated` shows resolvable 3.4.1. (source: `changelog`) |
| `flutter_inappwebview` | 6.0.0 → 6.1.5 | Every fix in that range is Windows, macOS or iOS: multiple Flutter windows, `callAsyncJavaScript` with JSON objects on Windows, `evaluateJavascript` on Windows, XCode 16 build, `shouldInterceptRequest` *implemented for Windows*. Flash ships Android only. 6.1.0 requires Flutter ≥3.24 (met). Harmless to bump, buys nothing. (source: `changelog`) |
| `xml` | 6.6.1 → 7.0.1 | Breaking and in the wrong direction: *"Namespaces of `XmlDocument.parse` and `XmlDocumentFragment.parse` are now resolved at parse-time"*, lower-level namespaces *"no longer available by default"*, `XmlBuilder.namespace`/`namespaces` deprecated for `namespaceUri`/`namespaceUris`. Flash parses OPML at `opml_service.dart:125` and builds it at `:387`. Pure risk on an import/export path, no benefit. (source: `changelog`) |
| `workmanager` | 0.9.0+3 → 0.10.10 | **Actively risky before launch.** 0.9.0 split into a federated architecture (`workmanager_android`). `AndroidManifest.xml:78-81` and `proguard-rules.pro` both hard-code `dev.fluttercommunity.workmanager.BackgroundWorker`, and WorkManager resolves the worker by **stored class name**, so a package move across that split breaks background refresh *silently*. I verified the class is still at `dev.fluttercommunity.workmanager.BackgroundWorker` in the resolved `workmanager_android-0.9.0+2`, so the manifest is correct today. 0.10.0 needs Flutter 3.38 (met). No fix Flash needs; the failure mode is invisible. (source: `changelog` + pub cache inspection) |
| `home_widget` | 0.9.4 → 0.10.0 | 0.10.0's two breaking changes are "Support Custom Fonts and Icons" and "Support Widget Previews". The changelog documents nothing for `saveWidgetData` or `updateWidget(androidName:)`, which is all Flash uses (`unread_widget_service.dart:49-50`). The only fix is iOS null handling. (source: `changelog`) |
| `firebase_app_check` | 0.4.7 → 0.4.8 | Both entries are Apple-only: "bump Firebase iOS SDK to 12.19.0" and "document native `configure()` workaround on Apple". Flash is Android only. Separately: `activate(androidProvider:)` was deprecated back in 0.4.1+1 in favour of `providerAndroid`, and `app_check_config.dart:34-35` already uses the current form. (source: `changelog`) |
| `shimmer` | 3.0.0 → 4.0.0 | `pub outdated` shows resolvable 3.0.0, i.e. 4.0.0 needs a constraint change. Single decorative use at `shimmer_card.dart:31`. Churn. |
| Patch churn | `firebase_core` 4.14→4.15, `sqflite` 2.4.2→2.4.2+1, `html` 0.15.6→0.15.7, `flutter_svg` 2.2.4→2.3.0, `path_provider` 2.1.5→2.1.6, the `url_launcher_*` platform packages | Nothing Flash calls changed. Trading a known-good lock for novelty two weeks before review. |
| `js` (discontinued) | 0.6.7 | Transitive, pulled through the Firebase web packages, never built for Android. Not actionable from Flash. |

---

## Verified, with no finding

Recorded so this ground does not get re-audited.

| Checked | Result | Source |
|---|---|---|
| Deprecated Flutter APIs | **None.** 0 hits for `withOpacity(`, `WillPopScope`, `MaterialState`, `textScaleFactor`, `ButtonBar`, `surfaceVariant`, `onBackground` across `lib/`. Theme uses `withValues` (`app_theme.dart:145, 793, 1005`), `WidgetStateProperty` (`:673-691, 787-793`), `CardThemeData` (`:760, 977`). Back handling uses `PopScope` with `onPopInvokedWithResult` (`app.dart:1360-1364, 1513-1523`). | `flutter analyze`, grep |
| Play target API requirement | **Compliant.** Play requires API 36 for new apps and updates from 31 Aug 2026 (extension to 1 Nov 2026 on request). Flash targets 36. Raising to 37 is neither required nor permitted here — CLAUDE.md is right. | live Android developer docs |
| Cloud model name | **Valid.** `gemini-3.5-flash-lite` is listed as a supported stable general-use model, "Retirement: No earlier than 2027-07-21" — a longer runway than `gemini-3.1-flash-lite` (2027-05-07) or `gemini-3.5-flash` (2027-05-19). This matters because `generativeModel` does no validation: *"there is no validation at creation time to verify if the provided model string is supported; invalid model identifiers will cause subsequent content generation attempts to fail."* Gemini 2.5 models shut down October 2026 — Flash is not on one. | `Context7` `/websites/pub_dev_firebase_ai` + live Firebase models page |
| App Check wiring | **Correct.** Explicit `appCheck:` passing is only required "for Flutter plugin v3.11.0 or lower"; Flash resolves `firebase_ai` 4.0.0. See B4 for the one thing worth adding. | `Context7` `/websites/firebase_google_ai-logic` |
| Gson 2.8.9 (transitive, via `flutter_local_notifications` 18.0.1) | **No known vulnerabilities.** OSV API query for `com.google.code.gson:gson@2.8.9` (Maven) returned `{}`. | `api.osv.dev` |
| Exact-alarm / scheduled notifications | **Not applicable.** Zero hits for `zonedSchedule`, `AndroidScheduleMode`, `exactAllowWhileIdle`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM` across `lib/` and `android/`. Flash only calls `show()`. Android 13+ `POST_NOTIFICATIONS` is declared (`AndroidManifest.xml:5`) and requested (`main.dart:60`). | grep |
| SQLite feature compatibility | **Safe.** Zero uses of `DROP COLUMN`, `RETURNING`, `STRICT`, generated columns or JSON functions in `lib/db/` or `lib/repositories/`. `database.dart:69` and `:572` already record why. Device SQLite 3.32.2 is sufficient for everything the 19 migrations do. | grep |
| WebView hardening | **Sensible defaults kept.** `javaScriptCanOpenWindowsAutomatically: false`, `supportMultipleWindows: false`, `disableContextMenu: true`, plus `onCreateWindow` returning false (`article_detail_pane.dart:445-497`). `mixedContentMode` is left unset, which falls through to Android WebView's own default of `MIXED_CONTENT_NEVER_ALLOW` for targetSdk ≥21. **Caveat:** the Context7 page documents `mixedContentMode` but does not state its default, so that last step rests on the Android platform default, not on the plugin's docs. | `Context7` `/websites/inappwebview_dev`, grep |
| `shouldInterceptRequest` usage | **Correct.** *"To be able to listen this event, you must set `InAppWebViewSettings.useShouldInterceptRequest` to `true`"* — Flash does (`article_detail_pane.dart:448`), and the comment at `:446-447` says exactly why. Returning `null` to load as usual is the documented contract, matching `:491`. | `Context7` `/pichillilorenzo/inappwebview.dev` |
| `pubspec.lock` integrity | **Untouched.** `git status --porcelain pubspec.lock pubspec.yaml` and `git diff pubspec.lock pubspec.yaml` are both empty after the pass. `pub outdated` is read-only and no `pub get` or `pub upgrade` was run. | `git` |

---

## Libraries Context7 did not cover, or covered with stale content

**Stale content, flagged where used:**

- `/websites/developers_google_ml-kit` — its get-started snapshot shows
  `com.google.mlkit:genai-prompt:1.0.0-beta2`, while Google Maven's own release
  metadata says the current release is `1.0.0-beta4`. The known-issues and
  release-notes entries in the same snapshot are newer (they reference beta3 and
  beta4 and a July 2026 release), so the snapshot is internally inconsistent.
  **Version facts in B3 come from Google Maven, not Context7.**
- `/websites/firebase_google_ai-logic` — the "Available model names" entry exists
  but carries no actual list of strings. **The model list in B8 and in
  "Verified" comes from the live docs page**, fetched directly.

**No Context7 query made; fell back to pub.dev changelogs** (labelled `changelog`
at every point of use): `workmanager`, `flutter_local_notifications`, `sqflite`,
`home_widget`, `share_plus`, `file_picker`, `url_launcher`, `app_badge_plus`,
`http`, `dart_rss`, `xml`, `html`, `cached_network_image`, `flutter_svg`,
`shimmer`, `flutter_lints`, `firebase_app_check`.

This was a deliberate budget choice. For these the question was "what broke
between the version Flash has and the version it could have", and a changelog
answers that more precisely and more cheaply than API documentation, which
describes only the current version. Context7 calls were spent on the four
highest-risk surfaces where *current API shape* was the actual question.

**Android artifact versions** came from Google Maven `maven-metadata.xml`
directly, which is authoritative in a way no documentation snapshot is.

---

## Deliberately not checked

- **Anything requiring a connected device.** No device was used at any point in
  this pass. Several findings above note where device verification is needed
  *before the change ships* — that is a note for whoever implements them, not
  something this audit did.
- **The Firebase console.** App Check enforcement status, whether the Play
  Integrity API is linked, whether the Play app-signing certificate is registered,
  and which debug tokens exist. None of this is visible from the repository, and
  all of it now matters: App Check became **automatically enforced for the Gemini
  API in July 2026** (source: `Context7`, `/websites/firebase_google_ai-logic`),
  which is already in the past. If that configuration is wrong, every cloud
  summary fails for every tester and the code in `gemini_cloud_service.dart` is
  blameless. **This is the single highest-value thing David can check that I
  cannot.**
- **Gradle's actually-resolved transitive Android dependency graph.** Would need a
  `./gradlew :app:dependencies` run. The Gson version was taken from the repo's own
  note at `proguard-rules.pro:23-24` and checked against OSV; other transitives
  were not enumerated.
- **`dart_rss` (3.0.3) and `http` (1.6.0).** Both already at latest; there is no
  gap to audit. `dart_rss`'s `RssFeed.parse` / `AtomFeed.parse` usage at
  `rss_service.dart:188-193, 342-352` is unchanged and current.
- **Whether flutter_lints 5's *removed* const rules currently produce findings.**
  They cannot — `flutter analyze` reports zero issues under the current rule set,
  which includes them.
- **Upgrading Flutter itself.** Out of scope for a dependency audit, and it is the
  gate on `cached_network_image` 4.0.0. 3.41.6 is six months old; worth a separate
  decision after production review, not before it.
- **Runtime behaviour, performance and UI.** This pass compared code against
  documentation. It did not run the app, run the test suite, or profile anything.

---

## Rules-of-the-pass compliance

- **No app code was changed.** The only file created is this one. `git status`
  before and after shows the same five pre-existing untracked files
  (`AGENTS.md`, `AUDIT_REPORT_2026-09-08.md`, `PROMPT-single-prd-and-cleanup.md`,
  `QA-INVENTORY.md`, `QA-LOG.md`) and no modifications.
- **`pubspec.lock` was not rewritten.** Verified by `git diff` after the pass.
  No `pub get`, no `pub upgrade`. The lint measurement in B5 ran against a copy
  of `lib/` and `test/` in a scratch directory outside the repository.
- **No version bump, no build, no install.** Per the instructions for this pass.
- **No device involvement of any kind**, in line with CLAUDE.md.
- **Nothing was delegated** to the local Qwen builder.
- **Decisions are reported, not made.**
