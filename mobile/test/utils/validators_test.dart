// Unit test untuk MyloValidators — pure Dart, tidak butuh mock atau widget tree.
// Test ini menjamin aturan validasi form di seluruh app tetap konsisten.

import 'package:flutter_test/flutter_test.dart';
import 'package:mylo/core/utils/validators.dart';

void main() {
  group('required', () {
    test('null/empty/whitespace → error', () {
      expect(MyloValidators.required(null), contains('kosong'));
      expect(MyloValidators.required(''), contains('kosong'));
      expect(MyloValidators.required('   '), contains('kosong'));
    });

    test('non-empty → null', () {
      expect(MyloValidators.required('halo'), isNull);
    });

    test('custom label muncul di pesan', () {
      expect(MyloValidators.required(null, 'Nama'), 'Nama tidak boleh kosong');
    });
  });

  group('email', () {
    test('valid', () {
      expect(MyloValidators.email('a@b.co'), isNull);
      expect(MyloValidators.email('test.user@example.com'), isNull);
      expect(MyloValidators.email('a-b@c-d.co'), isNull);
    });

    test('null/empty → "Email tidak boleh kosong"', () {
      expect(MyloValidators.email(null), 'Email tidak boleh kosong');
      expect(MyloValidators.email(''), 'Email tidak boleh kosong');
    });

    test('format invalid → "Format email tidak valid"', () {
      expect(MyloValidators.email('notanemail'), contains('tidak valid'));
      expect(MyloValidators.email('a@b'), contains('tidak valid'));
      expect(MyloValidators.email('@b.co'), contains('tidak valid'));
    });
  });

  group('password', () {
    test('null/empty → error', () {
      expect(MyloValidators.password(null), contains('kosong'));
      expect(MyloValidators.password(''), contains('kosong'));
    });

    test('< 8 char → error', () {
      expect(MyloValidators.password('1234567'), contains('minimal 8'));
    });

    test('>= 8 char → null', () {
      expect(MyloValidators.password('12345678'), isNull);
      expect(MyloValidators.password('verylongpassword'), isNull);
    });
  });

  group('confirmPassword', () {
    test('match → null', () {
      expect(MyloValidators.confirmPassword('abc', 'abc'), isNull);
    });

    test('mismatch → "tidak sama"', () {
      expect(MyloValidators.confirmPassword('abc', 'xyz'), contains('tidak sama'));
    });

    test('empty → "wajib diisi"', () {
      expect(MyloValidators.confirmPassword('', 'abc'), contains('wajib'));
    });
  });

  group('username', () {
    test('valid', () {
      expect(MyloValidators.username('john_doe'), isNull);
      expect(MyloValidators.username('user.name123'), isNull);
    });

    test('< 3 char', () {
      expect(MyloValidators.username('ab'), contains('minimal 3'));
    });

    test('> 30 char', () {
      expect(MyloValidators.username('a' * 31), contains('maksimal 30'));
    });

    test('karakter ilegal', () {
      expect(MyloValidators.username('user name'), contains('Hanya huruf'));
      expect(MyloValidators.username('user@name'), contains('Hanya huruf'));
    });
  });

  group('phone (opsional)', () {
    test('kosong → null', () {
      expect(MyloValidators.phone(null), isNull);
      expect(MyloValidators.phone(''), isNull);
    });

    test('digit valid', () {
      expect(MyloValidators.phone('+62812345678'), isNull);
      expect(MyloValidators.phone('081234567890'), isNull);
    });

    test('terlalu pendek/panjang', () {
      expect(MyloValidators.phone('12345'), contains('tidak valid'));
      expect(MyloValidators.phone('1234567890123456'), contains('tidak valid'));
    });
  });

  group('otp', () {
    test('6 digit valid', () {
      expect(MyloValidators.otp('123456'), isNull);
    });

    test('panjang salah', () {
      expect(MyloValidators.otp('12345'), contains('6 digit'));
      expect(MyloValidators.otp('1234567'), contains('6 digit'));
    });

    test('non-digit ditolak', () {
      expect(MyloValidators.otp('12345a'), contains('hanya angka'));
    });
  });

  group('compose', () {
    test('mengembalikan error pertama yang ditemui', () {
      final v = MyloValidators.compose([
        (s) => MyloValidators.required(s),
        (s) => MyloValidators.email(s),
      ]);
      expect(v(''), contains('kosong'));
      expect(v('bukan-email'), contains('tidak valid'));
      expect(v('a@b.co'), isNull);
    });
  });
}
