import 'package:flutter_test/flutter_test.dart';
import 'package:easy_authenticator/totp.dart';

void main() {
  test('RFC 6238 SHA1 8 digit test vector', () {
    const account = AuthAccount(id: '1', issuer: 'RFC', name: 'test', secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', digits: 8);
    expect(totp(account, now: DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true)), '94287082');
  });
  test('otpauth URI import', () {
    final account = parseOtpAuth('otpauth://totp/Example:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example');
    expect(account.issuer, 'Example');
    expect(account.name, 'alice@example.com');
  });
}
