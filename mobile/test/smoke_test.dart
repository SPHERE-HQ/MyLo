// Smoke test minimal — pastikan SDK Flutter, pubspec, dan test runner OK.
// Tambahkan widget test / unit test sesungguhnya di file lain di folder ini
// (file harus berakhir `_test.dart`) seiring fitur dibangun.

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mylo smoke test', () {
    test('Dart sanity', () {
      expect(1 + 1, equals(2));
      expect('mylo'.toUpperCase(), equals('MYLO'));
    });

    test('list & map operations', () {
      final list = [1, 2, 3];
      expect(list.length, 3);
      expect(list.fold<int>(0, (a, b) => a + b), 6);

      final map = <String, int>{'a': 1, 'b': 2};
      expect(map['a'], 1);
      expect(map.containsKey('c'), isFalse);
    });

    test('async future berjalan', () async {
      final value = await Future.value(42);
      expect(value, 42);
    });
  });
}
