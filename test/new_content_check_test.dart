import 'package:flutter_test/flutter_test.dart';
import 'package:flash/reading/new_content_check.dart';

void main() {
  group('NewContentCheck.hasNew', () {
    test('false when after is a subset of before', () {
      expect(NewContentCheck.hasNew({1, 2, 3}, [2, 3]), isFalse);
    });

    test('false when after exactly matches before', () {
      expect(NewContentCheck.hasNew({1, 2, 3}, [1, 2, 3]), isFalse);
    });

    test('true when after contains an id not in before', () {
      expect(NewContentCheck.hasNew({1, 2, 3}, [10, 1, 2, 3]), isTrue);
    });

    test('true when after is entirely new ids', () {
      expect(NewContentCheck.hasNew({}, [1, 2, 3]), isTrue);
    });

    test('false when both are empty', () {
      expect(NewContentCheck.hasNew({}, []), isFalse);
    });

    test('a null id is not counted as new against a null id', () {
      // Defensive: a persisted article always has an id, so this case does
      // not arise in practice. It is pinned to the conservative answer —
      // nulls compare equal, so an unidentifiable row can never be the thing
      // that yanks the list to the top.
      expect(NewContentCheck.hasNew({null}, [null]), isFalse);
    });
  });
}
