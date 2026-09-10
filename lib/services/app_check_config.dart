import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Which App Check attestation provider this build uses.
///
/// Play Integrity attests that the running app is a build Google Play
/// recognises. A locally-built APK is not distributed by Play, so it fails
/// attestation, App Check refuses to issue a token, and **every cloud summary
/// fails** — on exactly the devices used for testing, looking for all the world
/// like the Firebase migration is broken when it is working correctly.
///
/// So the provider is chosen by a compile-time flag, deliberately **not** by
/// `kDebugMode`: the local builds in question are `--release` builds, so
/// `kDebugMode` is false for them and would pick the very provider that cannot
/// work.
///
///   * local device builds — `--dart-define=APP_CHECK_DEBUG=true`
///   * the AAB uploaded to Play — built without it, so Play Integrity applies
///
/// A debug-provider build prints an App Check debug token to logcat on first
/// launch, which has to be registered in the Firebase console (App Check →
/// Apps → Manage debug tokens) before that device can reach the model. Until
/// it is, summaries fail on that device and that is expected, not a bug.
///
/// A registered debug token bypasses attestation entirely: treat one like a
/// key. It is generated per device at runtime and read from logcat — it must
/// never be committed.
const bool kAppCheckDebug = bool.fromEnvironment('APP_CHECK_DEBUG');

/// The selection itself, as a pure function so it can be asserted without a
/// platform channel. Pinned by gemini_cloud_service_test.dart.
@visibleForTesting
AndroidProvider appCheckProviderFor({required bool debug}) =>
    debug ? AndroidProvider.debug : AndroidProvider.playIntegrity;

/// What `main()` passes to `FirebaseAppCheck.activate`.
final AndroidProvider appCheckAndroidProvider =
    appCheckProviderFor(debug: kAppCheckDebug);
