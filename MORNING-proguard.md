# Device list — the release-build fix

**0.9.2+27 on the Lenovo and the Pixel.** Pushed through `5c4141a`.
**1678 passing, 1 skipped, analyzer clean.**

**The Samsung M51 is still off USB.** It has not reconnected all session, so it
did **not** get this build. One `adb install -r` when it does — and it is the
one device where you can still see the bug, so it is worth catching before you
update it.

---

## It is fixed, and I verified it rather than inferring it

Controlled before/after on your Lenovo, same action, release builds throughout:

| | R8 on, no rules | R8 **off** | R8 on **+ rules** |
|---|---|---|---|
| Turn "Icon badge" off with a notification live | **threw**, notification stayed | clean, dismissed | **clean, dismissed** |

The middle column is the diagnosis you asked for: disabling R8 made the
exception disappear, which is what proves it was a shrinker problem and not
something else wearing its clothes.

## The thing worth knowing, if you read nothing else

**The obvious fix was already in the build and did nothing.**

`-keepattributes Signature` is what everyone reaches for, including me in my
last report. It was already there — AGP ships it inside
`proguard-android-optimize.txt` — sitting at line 125 of the rule set of a
build that crashed anyway.

The real cause is R8 **full mode**, the AGP 8 default: it honours
`-keepattributes` only for classes that are **also** matched by a `-keep` rule.
Nothing matched the anonymous `TypeToken` inside the plugin, so its signature
was stripped regardless. The fix is the `-keep` pair, not the attribute.

If I had taken my own earlier suggestion on faith, I would have shipped a
no-op, watched it not work, and had no idea why.

## What to check by hand

### 1. The one that was broken

Open Quick settings → turn **Icon badge** off while a Flash notification is in
the shade. **It should vanish.** Turn it back on.

Before this build, that did nothing at all — and neither did reading
everything. The notification was unremovable by the app.

### 2. Mark everything read

**I did not run this one, deliberately.** It is the same `_clear()` →
`cancel()` call as the toggle above, so it is covered by the same fix, and
running it would have wiped 318 unread articles off your tablet to prove
something I had already proved a reversible way. Worth you doing once.

### 3. Keyword alerts and the group summary

Already verified on the Lenovo, and this is the first time they have **ever**
fired on that device: two alerts posted, both `color=0xff15868e`, plus the
group summary reading **"2 keyword alerts"**. Both channels exist at the right
importance. I added two keywords to test and **deleted both afterwards** — your
keyword list is empty again, exactly as I found it.

Three alert notifications may still be sitting in the tablet's shade. They are
AUTO_CANCEL, so tapping or swiping clears them; the Alerts entries behind them
were removed with the keywords.

### 4. The widget

**Not verified, and it cannot be from here: there is no Flash widget on either
home screen.** What I could confirm is that the provider itself survived R8 —
`dumpsys appwidget` reports it with `zombie=false` on both devices, which a
stripped or renamed provider would not be.

If you place one, that closes the last open item on this list.

### 5. First launch after updating, on any device

The plugin's maintainer notes the fix **is not retroactive**: a bad blob
written by a broken build stays bad in storage until it is rewritten. Flash
never schedules notifications, so its list should always be empty — but the
first launch after updating is the moment to watch, and the Samsung is the one
device that will make that jump from a broken build.

---

## The bigger finding, which was your actual question

**The app had no ProGuard configuration at all.** Nothing had ever been kept.
This crash was just the first stripped thing anyone noticed.

I audited all 15 Android plugins for reflection, Gson, runtime generics and
string-named resource lookup. **Nothing else is broken.** Two ship their own
rules; the rest either need none or are covered by rules arriving inside their
own dependencies.

**One thing you should not tidy up.** Background refresh survives only by
accident, twice over. `WorkManager` stores `BackgroundWorker`'s *class name* in
its database and looks it up reflectively later, so a rename would silently
stop background refresh — most visibly *after an app update*. It is saved by
`androidx.work`'s own bundled rules, and by this line in our manifest:

```xml
<service android:name="dev.fluttercommunity.workmanager.BackgroundWorker"
         tools:ignore="Instantiatable"/>
```

That declaration is **semantically wrong** — a worker is not a Service, which
is exactly why it carries a lint suppression — but it makes AGP emit a hard
keep on that class. It reads like dead config somebody forgot to delete. It is
load-bearing.

**Your call, not mine:** one line in `proguard-rules.pro` would make that
independent of both accidents:

```
-keep class dev.fluttercommunity.workmanager.BackgroundWorker { *; }
```

I did not add it, because you scoped this pass to the notification path and
this is a different subsystem.

**The other decision waiting for you:** `flutter_local_notifications` **19.0.0**
bumps Gson to 2.12, which ships these rules itself and makes our whole block
unnecessary. It is a breaking upgrade — Flutter ≥ 3.22, Dart ≥ 3.4, minSdk 21,
Java 11, plus an iOS `zonedSchedule` signature change. Not launch work.

---

## What the suite can and cannot do here

It **cannot see this class of bug at all**, and never will: `flutter test` runs
a debug VM on the host, and R8 only exists in a release build. 1672 tests
passed while this shipped to every tester.

So `proguard_rules_test.dart` does not test behaviour. It guards the *file* —
because the realistic regression is somebody deleting a page of comments they
do not recognise, and that deletion is completely silent: the build still
succeeds and the app still launches.

It also asserts nobody ever adds a `proguardFiles` declaration to
`build.gradle.kts`. Flutter already wires our rules file and **appends** to its
own defaults; declaring it again could *replace* them, which would be a much
bigger and much quieter breakage than the one just fixed.

This is written up as handoff **10.5**, beside the test-font rule it rhymes
with. The fix itself is **section 16**.

**Cost of the rules: 16,384 bytes.** For reference, turning R8 off entirely
would add about 7 MB — shrinking is worth having, it just needed configuring.
