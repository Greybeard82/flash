// The release-build ProGuard rules.
//
// **This suite cannot see the bug these rules fix, and never will.** The bug
// is R8 stripping a generic signature, R8 runs only on a release build, and
// `flutter test` runs a debug VM on the host with no R8 anywhere near it. A
// green suite says exactly nothing about whether the notification path works
// on a device. That is the same one-directional-trust problem as the test
// font in handoff 10.3.
//
// So these tests do not assert behaviour. They assert that the *file* which
// buys the behaviour still exists and still says the load-bearing things,
// because the realistic failure is somebody tidying away a file of comments
// they do not recognise. Deleting it is silent: the build still succeeds and
// the app still launches.
//
// Rule 10.4 applies to this file with unusual force. proguard-rules.pro
// carries long `#` comments that QUOTE the rule text in order to explain why
// the obvious one-line fix is not the fix. A whole-file `contains` would
// match that prose and pass with the rules themselves deleted, so every
// assertion below runs against comment-stripped source.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The file with every `#` comment removed, so an assertion cannot be
/// satisfied by a comment that merely mentions the rule.
String _rules() {
  final raw = File('android/app/proguard-rules.pro').readAsStringSync();
  return raw
      .split('\n')
      .map((l) {
        final hash = l.indexOf('#');
        return hash == -1 ? l : l.substring(0, hash);
      })
      .join('\n');
}

void main() {
  group('android/app/proguard-rules.pro', () {
    test('exists at the exact path Flutter looks for', () {
      // FlutterPlugin.kt does:
      //   if (File("${project.projectDir}/proguard-rules.pro").exists()) {
      //       proguardFile("proguard-rules.pro")
      //   }
      // projectDir for the app module is android/app, so the name and the
      // location are both load-bearing. Renaming it silently unwires it.
      expect(File('android/app/proguard-rules.pro').existsSync(), isTrue,
          reason: 'Flutter wires this exact path automatically. If it is gone, '
              'every release build throws PlatformException(Missing type '
              'parameter.) out of plugin.cancel() and the unread notification '
              'can never be dismissed.');
    });

    test('keeps the generic signature attribute', () {
      expect(_rules(), contains('-keepattributes Signature'));
    });

    test('keeps TypeToken and its subclasses — THE actual fix', () {
      // These two are the ones that matter. `-keepattributes Signature` alone
      // was already present via AGP's proguard-android-optimize.txt in a build
      // that still crashed: under R8 full mode -keepattributes only applies to
      // classes ALSO matched by a -keep rule.
      final code = _rules();
      expect(code, contains('class com.google.gson.reflect.TypeToken'),
          reason: 'without this the anonymous TypeToken subclass in '
              'loadScheduledNotifications() loses its generic signature');
      expect(code, contains('class * extends com.google.gson.reflect.TypeToken'),
          reason: 'the subclass rule is the one that actually covers the '
              'anonymous `new TypeToken<ArrayList<NotificationDetails>>() {}`');
    });

    test('the TypeToken keeps allow obfuscation, so they cost nothing', () {
      // Deliberately not a blanket `-keep class com.google.gson.** { *; }`.
      // These let R8 still rename and shrink; only the signature is retained.
      // The measured cost of this whole file was 16 KB.
      for (final line in _rules()
          .split('\n')
          .where((l) => l.contains('com.google.gson.reflect.TypeToken'))) {
        expect(line, contains('allowobfuscation'),
            reason: 'a keep rule that also pins the name would grow the APK '
                'for no benefit: $line');
      }
    });

    test('build.gradle.kts does NOT declare proguardFiles itself', () {
      // **This is the trap worth guarding.** Flutter already calls
      // proguardFiles(proguard-android-optimize.txt, flutter_proguard_rules.pro)
      // and then appends ours. An app-side `proguardFiles(...)` in the release
      // block can REPLACE that set rather than add to it, which would drop
      // Flutter's own rules — a much larger and much quieter breakage than the
      // one being fixed here.
      final gradle = File('android/app/build.gradle.kts')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(gradle, isNot(contains('proguardFiles')),
          reason: 'Flutter wires android/app/proguard-rules.pro on its own; '
              'declaring proguardFiles here risks replacing Flutter defaults');
      expect(gradle, isNot(contains('isMinifyEnabled')),
          reason: 'Flutter sets this to true for release. A stray '
              'isMinifyEnabled = false would disable the shrinking these '
              'rules exist for — and was exactly the temporary diagnostic '
              'used to confirm the bug.');
    });

    test('the resource-side twin is still there', () {
      // keep.xml is the same lesson on the resource side: shrinking is on and
      // invisible, and the notification icon is resolved by string name. If
      // this goes, notifications lose their icon rather than their cancel.
      final keep = File('android/app/src/main/res/raw/keep.xml');
      expect(keep.existsSync(), isTrue);
      expect(keep.readAsStringSync(), contains('ic_stat_flash'));
    });
  });
}
