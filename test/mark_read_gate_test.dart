// MarkReadGate tests.
//
// Written independently of the implementation. The gate is the safety
// property behind "the list never marks anything read unless the user
// scrolled it": FeedScreen._onScroll is a ScrollController listener and
// cannot distinguish a finger from a jumpTo, so the gate carries that
// information alongside it.
//
// Covered behaviours:
//  1. Closed on construction — nothing is eligible before anything moved
//  2. A user scroll opens it
//  3. A programmatic scroll closes it
//  4. Both operations are idempotent
//  5. A programmatic scroll after a user scroll still closes it — the order
//     that actually occurs on a refresh, and the one the bug depended on

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/utils/mark_read_gate.dart';

void main() {
  test('starts closed', () {
    expect(MarkReadGate().isOpen, isFalse,
        reason: 'a list that has never been scrolled has nothing above the '
            'viewport to mark read');
  });

  test('a user scroll opens it', () {
    final gate = MarkReadGate()..open();
    expect(gate.isOpen, isTrue);
  });

  test('a programmatic scroll closes it', () {
    final gate = MarkReadGate()
      ..open()
      ..close();
    expect(gate.isOpen, isFalse);
  });

  test('opening twice is the same as opening once', () {
    final gate = MarkReadGate()
      ..open()
      ..open();
    expect(gate.isOpen, isTrue);
  });

  test('closing twice is the same as closing once', () {
    final gate = MarkReadGate()
      ..open()
      ..close()
      ..close();
    expect(gate.isOpen, isFalse);
  });

  test('a refresh after normal scrolling leaves the gate closed', () {
    // The exact sequence from the bug report: the user scrolls, pulls to
    // refresh, new articles arrive above the viewport, the list jumps to the
    // top. Nothing may be marked read until the user scrolls again.
    final gate = MarkReadGate()..open(); // user scrolled down the list
    gate.close(); // _resetScrollToTop, before jumpTo(0)

    expect(gate.isOpen, isFalse,
        reason: 'the articles the refresh just fetched must not be read by '
            'the jump that follows it');

    gate.open(); // the user scrolls again, of their own accord
    expect(gate.isOpen, isTrue);
  });
}
