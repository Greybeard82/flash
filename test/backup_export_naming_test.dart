// The filename `LocalBackupService` proposes to the system file picker.
//
// Export used to write a temp file and hand it to `Share.shareXFiles`, which
// cannot save to the device: ACTION_SEND targets apps that accept a file, and
// "the phone's storage" is not an app. Export now goes through the Storage
// Access Framework via `FilePicker.saveFile`, which opens the system picker in
// create mode — the user chooses the folder and the filename, and the plugin
// writes the bytes.
//
// That makes the *proposed* filename the only part of the naming still under
// our control, and the one part worth pinning.
//
// `saveFile` is a platform channel and cannot be exercised here. The stamp is
// pulled out into `backupFileName` precisely so the half that is pure logic can
// be asserted without a picker; the picker half is covered by the manual device
// pass in MANUAL_QA.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/local_backup_service.dart';

void main() {
  test('the stamp is date and time to the minute, zero-padded', () {
    expect(
      LocalBackupService.backupFileName(DateTime(2026, 9, 9, 14, 37)),
      'flash_backup_20260909_1437.json',
    );
  });

  test('single-digit month, day, hour and minute are all padded', () {
    // 2026-01-02 03:04 — every field one digit, so an unpadded implementation
    // produces flash_backup_202612_34.json and this is what catches it.
    expect(
      LocalBackupService.backupFileName(DateTime(2026, 1, 2, 3, 4)),
      'flash_backup_20260102_0304.json',
    );
  });

  test('midnight is 0000, not blank or 2400', () {
    expect(
      LocalBackupService.backupFileName(DateTime(2026, 12, 31, 0, 0)),
      'flash_backup_20261231_0000.json',
    );
  });

  // DO NOT "simplify" this back to a date-only stamp. It looks like a pointless
  // test and it is not.
  //
  // file_picker on Android has a defect when the chosen filename already
  // exists: it writes the new bytes over the old file *without truncating*. A
  // smaller export landing on a larger one leaves the tail of the previous file
  // behind, and the result is valid JSON followed by garbage — which parses far
  // enough to look fine and then fails on restore.
  //
  // The fix is not to patch the plugin. It is to never propose a name that
  // collides. Date-only collided on the second export of any given day, which
  // is exactly when a user exports twice: before and after a change they are
  // unsure about.
  test('two exports a minute apart do not propose the same filename', () {
    final first = LocalBackupService.backupFileName(DateTime(2026, 9, 9, 14, 37));
    final second = LocalBackupService.backupFileName(DateTime(2026, 9, 9, 14, 38));
    expect(first, isNot(second));
  });

  test('two exports on the same day are distinguished by the time', () {
    // The specific case date-only got wrong: same date, hours apart.
    final morning = LocalBackupService.backupFileName(DateTime(2026, 9, 9, 9, 15));
    final evening = LocalBackupService.backupFileName(DateTime(2026, 9, 9, 21, 15));
    expect(morning, isNot(evening));
    expect(morning, 'flash_backup_20260909_0915.json');
    expect(evening, 'flash_backup_20260909_2115.json');
  });

  test('the extension is .json, so the picker filters and saves consistently',
      () {
    // saveFile is called with FileType.custom + allowedExtensions ['json'];
    // a name disagreeing with that is how you get flash_backup.json.json.
    expect(
      LocalBackupService.backupFileName(DateTime(2026, 9, 9, 14, 37)),
      endsWith('.json'),
    );
  });
}
