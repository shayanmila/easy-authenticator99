import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class AuthAccount {
  final String id;
  final String issuer;
  final String name;
  final String secret;
  final int digits;
  final int period;
  final String algorithm;
  const AuthAccount({required this.id, required this.issuer, required this.name, required this.secret, this.digits = 6, this.period = 30, this.algorithm = 'SHA1'});
  Map<String, dynamic> toJson() => {'id': id, 'issuer': issuer, 'name': name, 'secret': secret, 'digits': digits, 'period': period, 'algorithm': algorithm};
  factory AuthAccount.fromJson(Map<String, dynamic> j) => AuthAccount(id: j['id'] as String, issuer: j['issuer'] as String, name: j['name'] as String, secret: j['secret'] as String, digits: j['digits'] as int? ?? 6, period: j['period'] as int? ?? 30, algorithm: j['algorithm'] as String? ?? 'SHA1');
}

List<int> decodeBase32(String input) {
  final s = input.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
  if (s.isEmpty) throw const FormatException('Secret cannot be empty');
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0, bits = 0;
  final bytes = <int>[];
  for (final char in s.split('')) {
    final n = alphabet.indexOf(char);
    if (n < 0) throw const FormatException('Invalid Base32 secret');
    buffer = (buffer << 5) | n;
    bits += 5;
    if (bits >= 8) { bits -= 8; bytes.add((buffer >> bits) & 255); buffer &= (1 << bits) - 1; }
  }
  if (bytes.isEmpty) throw const FormatException('Secret too short');
  return bytes;
}

String totp(AuthAccount account, {DateTime? now}) {
  final timestamp = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
  final counter = timestamp ~/ account.period;
  final msg = List<int>.generate(8, (i) => (counter >> (56 - i * 8)) & 255);
  final key = decodeBase32(account.secret);
  final digest = switch (account.algorithm.toUpperCase()) {
    'SHA256' => Hmac(sha256, key).convert(msg).bytes,
    'SHA512' => Hmac(sha512, key).convert(msg).bytes,
    _ => Hmac(sha1, key).convert(msg).bytes,
  };
  final offset = digest.last & 15;
  final binary = ((digest[offset] & 127) << 24) | (digest[offset + 1] << 16) | (digest[offset + 2] << 8) | digest[offset + 3];
  return (binary % pow(10, account.digits).toInt()).toString().padLeft(account.digits, '0');
}

AuthAccount parseOtpAuth(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || uri.scheme.toLowerCase() != 'otpauth' || uri.host.toLowerCase() != 'totp') throw const FormatException('Only otpauth://totp QR codes are supported');
  final q = uri.queryParameters;
  final label = Uri.decodeComponent(uri.pathSegments.join('/'));
  final issuer = (q['issuer'] ?? (label.contains(':') ? label.split(':').first : '')).trim();
  final name = (label.contains(':') ? label.substring(label.indexOf(':') + 1) : label).trim();
  final secret = q['secret'] ?? '';
  decodeBase32(secret);
  final digits = int.tryParse(q['digits'] ?? '6') ?? 6;
  final period = int.tryParse(q['period'] ?? '30') ?? 30;
  final algorithm = (q['algorithm'] ?? 'SHA1').toUpperCase();
  if (digits != 6 && digits != 8) throw const FormatException('Only 6 or 8 digit TOTP supported');
  if (period < 10 || period > 300) throw const FormatException('Invalid TOTP period');
  if (!['SHA1', 'SHA256', 'SHA512'].contains(algorithm)) throw const FormatException('Unsupported algorithm');
  return AuthAccount(id: DateTime.now().microsecondsSinceEpoch.toString(), issuer: issuer, name: name.isEmpty ? 'Account' : name, secret: secret, digits: digits, period: period, algorithm: algorithm);
}

String serializeAccounts(List<AuthAccount> accounts) => jsonEncode(accounts.map((e) => e.toJson()).toList());
List<AuthAccount> deserializeAccounts(String data) => (jsonDecode(data) as List).map((e) => AuthAccount.fromJson(Map<String, dynamic>.from(e as Map))).toList();
