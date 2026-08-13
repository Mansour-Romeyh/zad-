import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/services/url_opener.dart';

void main() {
  test('DefaultUrlOpener returns false for an unparseable url', () async {
    // A malformed URL must not throw — the caller shows a snackbar on false.
    const opener = DefaultUrlOpener();
    expect(await opener.open('::::not a url::::'), isFalse);
  });
}
