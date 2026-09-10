// The privacy policy link in Settings → About.
//
// Google Play requires the privacy policy to be reachable from inside the app,
// not only from the store listing. That makes this URL a release requirement
// rather than a nicety, and a typo in it is the kind of thing that passes code
// review, ships, and is found by a reviewer rejecting the build.
//
// The tile itself needs a widget test to exercise — tapping it calls
// url_launcher across a platform channel — and this project has no widget-test
// coverage for any screen (see the note in the 2026-08 audit). That gap is not
// new and is not closed here. What *is* cheap to pin is the constant, so it is.

import 'package:flutter_test/flutter_test.dart';

import 'package:flash/screens/settings_screen.dart';

void main() {
  test('the privacy policy URL is the one Play was given', () {
    expect(kPrivacyPolicyUrl, 'https://flashrssapp.github.io/privacy.html');
  });

  test('it is https', () {
    // A policy served over http would be rewritten or blocked by the browser
    // on a modern Android, and Play would reject the listing.
    final uri = Uri.parse(kPrivacyPolicyUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, isNotEmpty);
  });

  test('it parses as an absolute URL', () {
    // launchUrl silently returns false on a relative or malformed URI, which
    // would show as a tile that does nothing.
    expect(Uri.parse(kPrivacyPolicyUrl).isAbsolute, isTrue);
  });
}
