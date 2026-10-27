import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'totp.dart';

/// Password-encrypted portable backup. No plaintext secrets are written to disk.
class BackupCodec {
  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 310000, bits: 256);
  static final _random = Random.secure();
  static Uint8List _bytes(int n) => Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));
  static Future<SecretKey> _key(String password, List<int> salt) =>
      _kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  static Future<Uint8List> export(List<AuthAccount> accounts, String password) async {
    if (password.length < 12) throw const FormatException('Use a password of at least 12 characters');
    final salt = _bytes(16), nonce = _bytes(12);
    final key = await _key(password, salt);
    final box = await _cipher.encrypt(utf8.encode(serializeAccounts(accounts)), secretKey: key, nonce: nonce);
    final document = {
      'format': 'easy-auth-backup', 'version': 1, 'kdf': 'pbkdf2-sha256',
      'iterations': 310000, 'cipher': 'aes-256-gcm',
      'salt': base64Encode(salt), 'nonce': base64Encode(nonce),
      'data': base64Encode(box.cipherText), 'mac': base64Encode(box.mac.bytes)
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(document)));
  }
  static Future<List<AuthAccount>> restore(Uint8List bytes, String password) async {
    if (bytes.length > 5 * 1024 * 1024) throw const FormatException('Backup exceeds 5 MB');
    final obj = jsonDecode(utf8.decode(bytes));
    if (obj is! Map || obj['format'] != 'easy-auth-backup' || obj['version'] != 1 ||
        obj['kdf'] != 'pbkdf2-sha256' || obj['iterations'] != 310000 || obj['cipher'] != 'aes-256-gcm') {
      throw const FormatException('Unsupported backup format');
    }
    final salt = base64Decode(obj['salt'] as String), nonce = base64Decode(obj['nonce'] as String);
    final mac = base64Decode(obj['mac'] as String), data = base64Decode(obj['data'] as String);
    if (salt.length != 16 || nonce.length != 12 || mac.length != 16) throw const FormatException('Invalid backup header');
    final key = await _key(password, salt);
    final clear = await _cipher.decrypt(SecretBox(data, nonce: nonce, mac: Mac(mac)), secretKey: key);
    final accounts = deserializeAccounts(utf8.decode(clear));
    if (accounts.length > 10000) throw const FormatException('Too many accounts');
    for (final a in accounts) {
      decodeBase32(a.secret);
      if (a.period < 10 || a.period > 300 || (a.digits != 6 && a.digits != 8) ||
          !['SHA1','SHA256','SHA512'].contains(a.algorithm.toUpperCase())) throw const FormatException('Invalid account in backup');
    }
    return accounts;
  }
}
