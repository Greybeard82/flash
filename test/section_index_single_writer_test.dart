// One way to change which section is showing.
//
// The regression this pins: the sidebar's contextual actions are keyed by
// section, so `SectionActionsController.selectSection` has to be called every
// time the section changes. It was called from `_navigateTo` only — and
// `_navigateTo` is not how you get to Flash by pressing Back, by tapping an
// alert notification, or by finishing onboarding. Those four paths moved the
// user without moving the actions, so Flash could be on screen showing
// Alerts' buttons, or none at all.
//
// Patching those four call sites to each remember a second call would have
// left the same trap set for the fifth. Instead there is now exactly one
// writer, `_setCurrentIndex`, which does both — and this test is what keeps
// it that way. It reads the source rather than driving the widget, because
// what it is asserting is a property of the code, not of a rendered frame:
// no other line may assign `_currentIndex`.
//
// If this test fails, do not add the missing `selectSection` call next to the
// new assignment. Route the new path through `_setCurrentIndex` instead.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Assignments to `_currentIndex`, as `line number -> source line`.
///
/// Deliberately not a regex over the whole file in one go: the field's own
/// declaration and every read (`_currentIndex == 0`, `index: _currentIndex`)
/// have to be excluded, and doing that inline keeps the failure message able
/// to name the offending line.
Map<int, String> _assignments(List<String> lines) {
  final out = <int, String>{};
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    // The declaration, not an assignment to an existing field.
    if (line.contains('int _currentIndex = 0;')) continue;
    // `==`, `!=`, `>=` and friends are comparisons, not assignments.
    final match = RegExp(r'_currentIndex\s*=(?!=)').firstMatch(line);
    if (match != null) out[i + 1] = line.trim();
  }
  return out;
}

void main() {
  late List<String> lines;

  setUpAll(() {
    lines = File('lib/app.dart').readAsLinesSync();
  });

  test('_currentIndex is assigned in exactly one place', () {
    final found = _assignments(lines);

    expect(found, hasLength(1),
        reason: 'every way of changing section must go through '
            '_setCurrentIndex, which also tells SectionActionsController. '
            'Found assignments at lines ${found.keys.toList()}: '
            '${found.values.toList()}');
  });

  test('that one place is inside _setCurrentIndex', () {
    final assignedAt = _assignments(lines).keys.single;

    // Walk back to the nearest method signature above the assignment.
    var owner = '';
    for (var i = assignedAt - 1; i >= 0; i--) {
      final m = RegExp(r'^\s{0,4}(?:void|Future<void>)\s+(_\w+)\s*\(')
          .firstMatch(lines[i]);
      if (m != null) {
        owner = m.group(1)!;
        break;
      }
    }

    expect(owner, '_setCurrentIndex',
        reason: 'the single assignment moved out of the method that also '
            'notifies the controller, which is the whole point of it');
  });

  test('_setCurrentIndex notifies the controller', () {
    final start =
        lines.indexWhere((l) => l.contains('void _setCurrentIndex(int index)'));
    expect(start, isNot(-1), reason: 'the canonical setter has been renamed '
        'or removed — this test and the invariant it guards need revisiting');

    final body = lines.skip(start).take(8).join('\n');
    expect(body, contains('selectSection(index)'),
        reason: 'assigning the index without telling the controller is the '
            'original bug, now in one place instead of five');
  });

  test('every section-changing path routes through it', () {
    final source = lines.join('\n');
    // The five callers the QA pass identified, by the shape each one has.
    for (final caller in const [
      '_setCurrentIndex(kAlertsNavIndex)', // alert notification tap
      '_setCurrentIndex(1)', // end of onboarding
      '_setCurrentIndex(index)', // _navigateTo
      '_setCurrentIndex(0)', // the back handlers
    ]) {
      expect(source, contains(caller),
          reason: 'a known section-changing path stopped using the canonical '
              'setter: $caller');
    }

    // Three shells, three back handlers, all of them returning to Flash.
    final backHandlers = RegExp(r'_setCurrentIndex\(0\)').allMatches(source);
    expect(backHandlers, hasLength(3),
        reason: 'the phone shell is included deliberately even though it has '
            'no sidebar today — one rule, no exceptions to forget');
  });
}
