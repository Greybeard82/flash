# ProGuard / R8 rules for Flash.
#
# Flutter's Gradle plugin turns R8 and resource shrinking ON for every release
# build, and picks this file up automatically if it exists. From
# packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt:
#
#     isMinifyEnabled = true
#     isShrinkResources = FlutterPluginUtils.isBuiltAsApp(project)
#     proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"),
#                   flutterProguardRules)
#     if (File("${project.projectDir}/proguard-rules.pro").exists()) {
#         proguardFile("proguard-rules.pro")
#     }
#
# Two consequences worth knowing before editing anything here:
#
#   - There is nothing in app/build.gradle.kts to show shrinking is happening.
#     Do not "enable" it there, and do not add proguardFiles there either --
#     this file is already wired, and proguardFile() APPENDS, so Flutter's own
#     defaults still apply. Declaring them again risks replacing them.
#   - res/raw/keep.xml exists for exactly the same invisible reason, on the
#     resource side. The two files are the same lesson learned twice.

# ---------------------------------------------------------------------------
# Gson, pulled in transitively by flutter_local_notifications 18.0.1, which
# pins com.google.code.gson:gson:2.8.9.
# ---------------------------------------------------------------------------
# Without the rules below, EVERY release build throws
#
#     PlatformException(error, Missing type parameter.,
#                       java.lang.RuntimeException: Missing type parameter.)
#
# out of plugin.cancel(), and the unread-count notification can never be
# dismissed by the app -- not by reading everything, not by turning the
# setting off. Reproduced and fixed on device; see DESIGN-HANDOFF.md 16.
#
# THE OBVIOUS RULE IS NOT THE FIX, so do not "simplify" this to one line.
# `-keepattributes Signature` was ALREADY being applied before this file
# existed -- it arrives with AGP's own proguard-android-optimize.txt, and it
# is visible at line 125 of build/app/outputs/mapping/release/configuration.txt
# in a build that still crashed. What was missing is the -keep pair.
#
# The reason is R8 "full mode", which is the AGP 8 default and which this
# project does not opt out of (android.enableR8.fullMode is unset). Full mode
# honours -keepattributes only for classes that are ALSO matched by a -keep
# rule. The anonymous `new TypeToken<ArrayList<NotificationDetails>>() {}`
# inside loadScheduledNotifications() matched no -keep rule, so its generic
# signature was stripped, getGenericSuperclass() returned a raw Class, and
# Gson 2.8.9's TypeToken.getSuperclassTypeParameter threw.
#
# Sources, rather than memory:
#   - The plugin's example app, which its README points to:
#     <pub cache>/flutter_local_notifications-18.0.1/example/android/app/
#     proguard-rules.pro
#   - Gson's own consumer rules, META-INF/proguard/gson.pro, which Gson ships
#     and auto-applies from 2.11.0 onward. 2.8.9 predates that, which is why
#     they have to be vendored here:
#     https://github.com/google/gson/blob/main/gson/src/main/resources/META-INF/proguard/gson.pro
#   - MaikuB/flutter_local_notifications#2223, where this exact pair resolved
#     this exact exception.
#
# Note the README also links Gson's examples/android-proguard-example/
# proguard.cfg. That file was DELETED upstream on 2025-04-14 for being
# outdated and now 404s; gson.pro above replaced it.
#
# This whole block becomes unnecessary at flutter_local_notifications 19.0.0,
# which bumps Gson to 2.12 so the rules arrive on their own. That upgrade is a
# breaking change (Flutter >= 3.22, Dart >= 3.4, minSdk 21, Java 11, plus an
# iOS zonedSchedule signature change) and is deliberately not done here.

# Gson uses generic type information stored in a class file when working with
# fields. R8 removes it by default.
-keepattributes Signature

# For the @Expose annotation.
-keepattributes *Annotation*

-dontwarn sun.misc.**

# Retain generic signatures of TypeToken and its subclasses under R8 full mode.
# THESE TWO LINES ARE THE ACTUAL FIX.
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# The plugin registers a RuntimeTypeAdapterFactory in buildGson() for the
# StyleInformation hierarchy -- a second reflective surface on the same path
# that cancel() walks.
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# NotificationDetails carries @SerializedName fields. Without this R8 can null
# them out, which would be a quieter failure than the crash above: notifications
# that post but lose attributes.
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# ---------------------------------------------------------------------------
# WorkManager's background refresh worker.
# ---------------------------------------------------------------------------
# WorkManager does not construct BackgroundWorker. It persists the fully
# qualified CLASS NAME into its own Room database, and androidx.work's
# WorkerFactory later does Class.forName plus a 2-arg (Context, WorkerParameters)
# constructor lookup to run it. Rename or strip either and background refresh
# stops -- silently, with no crash to point at, and most visibly AFTER an app
# update, when the database still holds the previous build's name.
#
# This rule is the SECOND belt, and it is deliberate. Two other things already
# keep this class, and neither is something to rely on:
#
#   1. androidx.work's own AAR ships `-keepnames class * extends
#      androidx.work.ListenableWorker`. Inherited: a dependency bump that drops
#      below the version shipping those rules takes it away.
#   2. AndroidManifest.xml declares BackgroundWorker as a <service>. That
#      declaration is semantically WRONG -- a ListenableWorker is not a Service,
#      which is exactly why it carries tools:ignore="Instantiatable" -- but it
#      makes AGP emit a hard manifest-derived keep. It reads like dead config
#      somebody forgot to delete, and the next person to tidy it away would be
#      removing a load-bearing line by accident.
#
# The manifest line stays. This rule exists so that if either of those goes,
# background refresh does not go with it. Belt and belt, not belt and mistake.
-keep class dev.fluttercommunity.workmanager.BackgroundWorker { *; }
