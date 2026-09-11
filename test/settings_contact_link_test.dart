// The contact details in Settings → About.
//
// Google Play's News and Magazines policy requires contact information — an
// email address or a phone number — behind a URL that is reachable from inside
// the app *and* identical to the one declared in the Play Console. Those two
// drifting apart is a rejection, and it is not the kind of drift that shows up
// in review: both halves look fine on their own.
//
// So the constants are pinned here, exactly as kPrivacyPolicyUrl already is.
// Same limitation as that test: the tiles themselves need a widget test to
// exercise, since tapping one crosses a platform channel into url_launcher,
// and that gap is not closed here.

import 'package:flutter_test/flutter_test.dart';

import 'package:flash/screens/settings_screen.dart';

void main() {
  test('the support URL is the one declared to Play', () {
    // If this fails, the Play Console News and Magazines declaration has to
    // change in the same commit — not afterwards.
    expect(kSupportUrl, 'https://flashrssapp.github.io/support.html');
  });

  test('the support URL is absolute https', () {
    final uri = Uri.parse(kSupportUrl);
    expect(uri.isAbsolute, isTrue);
    expect(uri.scheme, 'https');
    expect(uri.host, isNotEmpty);
  });

  test('the contact address is the published one', () {
    expect(kContactEmail, 'flashrssapp@gmail.com');
  });

  test('the contact address survives being built into a mailto: URI', () {
    // This is the exact construction the Email us row launches. A stray space
    // or a missing @ would produce a URI that launchUrl refuses, showing as a
    // row that does nothing.
    final uri = Uri(scheme: 'mailto', path: kContactEmail);
    expect(uri.toString(), 'mailto:$kContactEmail');
    expect(kContactEmail, contains('@'));
    expect(kContactEmail.trim(), kContactEmail);
  });
}
