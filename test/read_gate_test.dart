import 'package:flutter_test/flutter_test.dart';
import 'package:flash/reading/read_gate.dart';

void main() {
  const grace = Duration(milliseconds: 600);

  ReadGateInput input({
    bool userInitiated = true,
    bool extentsStable = true,
    Duration sinceResume = const Duration(seconds: 10),
    bool pastMidpoint = true,
  }) =>
      ReadGateInput(
        userInitiated: userInitiated,
        extentsStable: extentsStable,
        sinceResume: sinceResume,
        pastMidpoint: pastMidpoint,
        resumeGrace: grace,
      );

  group('ReadGate.allows', () {
    test('allows a normal user scroll past the midpoint', () {
      expect(ReadGate.allows(input()), isTrue);
    });

    test('blocks an article that has not passed the midpoint', () {
      expect(ReadGate.allows(input(pastMidpoint: false)), isFalse);
    });

    test('blocks offset changes that did not originate from the user', () {
      expect(ReadGate.allows(input(userInitiated: false)), isFalse);
    });

    test('blocks while row extents are still settling', () {
      expect(ReadGate.allows(input(extentsStable: false)), isFalse);
    });

    test('blocks inside the resume grace window even for a real drag', () {
      expect(
        ReadGate.allows(input(sinceResume: const Duration(milliseconds: 100))),
        isFalse,
      );
    });

    test('allows once the resume grace window has elapsed', () {
      expect(
        ReadGate.allows(input(sinceResume: const Duration(milliseconds: 601))),
        isTrue,
      );
    });

    test('grace boundary is exclusive: exactly at the grace duration blocks', () {
      expect(ReadGate.allows(input(sinceResume: grace)), isFalse);
    });

    test('a single failing condition is enough to block', () {
      expect(
        ReadGate.allows(input(userInitiated: false, extentsStable: false)),
        isFalse,
      );
    });
  });
}
