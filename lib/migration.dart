import 'dart:convert';
import 'totp.dart';

/// Google Authenticator migration payload decoder.
/// All processing stays on-device; never log or transmit the payload.
class _Proto {
  final List<int> bytes;
  int pos = 0;
  _Proto(this.bytes);
  int varint() {
    var result = 0, shift = 0;
    while (pos < bytes.length && shift < 70) {
      final b = bytes[pos++];
      result |= (b & 127) << shift;
      if ((b & 128) == 0) return result;
      shift += 7;
    }
    throw const FormatException('Invalid migration payload');
  }
  List<int> chunk() {
    final length = varint();
    if (length < 0 || length > bytes.length - pos) throw const FormatException('Invalid payload length');
    final data = bytes.sublist(pos, pos + length);
    pos += length;
    return data;
  }
  void skip(int wire) {
    if (wire == 0) { varint(); return; }
    if (wire == 1) { if (pos + 8 > bytes.length) throw const FormatException('Truncated payload'); pos += 8; return; }
    if (wire == 2) { chunk(); return; }
    if (wire == 5) { if (pos + 4 > bytes.length) throw const FormatException('Truncated payload'); pos += 4; return; }
    throw const FormatException('Unsupported protobuf wire type');
  }
}
class MigrationBatch {
  final List<AuthAccount> accounts;
  final int index;
  final int size;
  final int batchId;
  const MigrationBatch(this.accounts, this.index, this.size, this.batchId);
}
MigrationBatch parseGoogleMigration(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'otpauth-migration' || uri.host != 'offline') throw const FormatException('Not a Google Authenticator transfer QR');
  final data = uri.queryParameters['data'];
  if (data == null || data.isEmpty) throw const FormatException('Missing transfer data');
  final decoded = base64.decode(base64.normalize(data.replaceAll(' ', '+')));
  if (decoded.length > 100000) throw const FormatException('Transfer too large');
  final p = _Proto(decoded);
  final accounts = <AuthAccount>[];
  var batchIndex = 0, batchSize = 1, batchId = 0;
  while (p.pos < p.bytes.length) {
    final tag = p.varint(), field = tag >> 3, wire = tag & 7;
    if (field == 1 && wire == 2) {
      final entry = _Proto(p.chunk());
      var secret = <int>[], name = '', issuer = '', algorithm = 1, digits = 1, type = 2;
      while (entry.pos < entry.bytes.length) {
        final t = entry.varint(), f = t >> 3, w = t & 7;
        if (w == 2 && f == 1) { secret = entry.chunk(); }
        else if (w == 2 && f == 2) { name = utf8.decode(entry.chunk()); }
        else if (w == 2 && f == 3) { issuer = utf8.decode(entry.chunk()); }
        else if (w == 0 && f == 4) { algorithm = entry.varint(); }
        else if (w == 0 && f == 5) { digits = entry.varint(); }
        else if (w == 0 && f == 6) { type = entry.varint(); }
        else { entry.skip(w); }
      }
      if (type != 2) continue; // HOTP has a counter, not a time-based code.
      if (secret.isEmpty || secret.length > 512) throw const FormatException('Invalid secret');
      final algo = switch (algorithm) { 1 => 'SHA1', 2 => 'SHA256', 3 => 'SHA512', _ => throw const FormatException('Unsupported algorithm') };
      final count = switch (digits) { 1 => 6, 2 => 8, _ => throw const FormatException('Unsupported digits') };
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
      var bits = 0, buffer = 0;
      final encoded = StringBuffer();
      for (final b in secret) {
        buffer = (buffer << 8) | b; bits += 8;
        while (bits >= 5) { bits -= 5; encoded.write(alphabet[(buffer >> bits) & 31]); }
        buffer &= (1 << bits) - 1;
      }
      if (bits > 0) encoded.write(alphabet[(buffer << (5 - bits)) & 31]);
      accounts.add(AuthAccount(id: DateTime.now().microsecondsSinceEpoch.toString() + '-${accounts.length}', issuer: issuer, name: name.isEmpty ? 'Account' : name, secret: encoded.toString(), algorithm: algo, digits: count));
    } else if (wire == 0 && field == 3) { batchSize = p.varint(); }
    else if (wire == 0 && field == 4) { batchIndex = p.varint(); }
    else if (wire == 0 && field == 5) { batchId = p.varint(); }
    else { p.skip(wire); }
  }
  if (batchSize < 1 || batchSize > 100 || batchIndex < 0 || batchIndex >= batchSize) throw const FormatException('Invalid transfer batch');
  if (accounts.isEmpty) throw const FormatException('No supported TOTP accounts found');
  return MigrationBatch(accounts, batchIndex, batchSize, batchId);
}
