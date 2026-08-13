import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/auth/widgets/phone_field.dart';

/// PhoneField.e164 is THE composition point for every phone the app sends
/// (login, register, reset) — Iraqi users near-universally type the local
/// leading-zero form (07701234567), which must never be sent as
/// +96407701234567.
void main() {
  String e164(String typed) => PhoneField.e164(TextEditingController(text: typed));

  group('PhoneField.e164', () {
    test('strips the local leading zero when applying the country prefix', () {
      expect(e164('07701234567'), '+9647701234567');
    });

    test('keeps an already-local number unchanged', () {
      expect(e164('7701234567'), '+9647701234567');
    });

    test('drops spaces and dashes', () {
      expect(e164('0770 123-4567'), '+9647701234567');
    });

    test('collapses a pasted full +964 number to a single prefix', () {
      expect(e164('+964 770 123 4567'), '+9647701234567');
      expect(e164('9647701234567'), '+9647701234567');
      expect(e164('+9640770 123 4567'), '+9647701234567');
    });

    test('does not eat a short number that merely starts with 964', () {
      // 10 digits or fewer starting with 964 is treated as local input,
      // not as a country code to strip.
      expect(e164('9641234567'), '+9649641234567');
    });

    test('trims surrounding whitespace', () {
      expect(e164(' 07701234567 '), '+9647701234567');
    });
  });

  /// Iraqi mobile numbers are 10 local digits starting with 7 (typed as
  /// 07XX XXX XXXX). The validator must accept every input shape e164
  /// normalizes and reject everything else before it reaches the API.
  group('PhoneField.isValidIraqiMobile', () {
    test('accepts the universal local leading-zero form', () {
      expect(PhoneField.isValidIraqiMobile('07701234567'), isTrue);
    });

    test('accepts the bare 10-digit local form', () {
      expect(PhoneField.isValidIraqiMobile('7701234567'), isTrue);
    });

    test('accepts formatting separators', () {
      expect(PhoneField.isValidIraqiMobile('0770 123-4567'), isTrue);
    });

    test('accepts pasted full +964 numbers', () {
      expect(PhoneField.isValidIraqiMobile('+964 770 123 4567'), isTrue);
      expect(PhoneField.isValidIraqiMobile('9647701234567'), isTrue);
      expect(PhoneField.isValidIraqiMobile('+9640770 123 4567'), isTrue);
    });

    test('rejects numbers that are too short', () {
      expect(PhoneField.isValidIraqiMobile('077012345'), isFalse);
      expect(PhoneField.isValidIraqiMobile('770123456'), isFalse);
    });

    test('rejects numbers that are too long', () {
      expect(PhoneField.isValidIraqiMobile('077012345678'), isFalse);
      expect(PhoneField.isValidIraqiMobile('77012345678'), isFalse);
    });

    test('rejects numbers that do not start with 7', () {
      expect(PhoneField.isValidIraqiMobile('01234567890'), isFalse);
      expect(PhoneField.isValidIraqiMobile('1234567890'), isFalse);
    });

    test('rejects non-numeric input', () {
      expect(PhoneField.isValidIraqiMobile('not a phone'), isFalse);
      expect(PhoneField.isValidIraqiMobile(''), isFalse);
    });
  });
}
