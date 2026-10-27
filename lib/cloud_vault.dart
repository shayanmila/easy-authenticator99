import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backup.dart';
import 'totp.dart';

/// Phase 2 manual encrypted vault. Never transmits plaintext TOTP material.
class CloudVaultService {
  static Future<void> firstUpload(List<AuthAccount> accounts, String masterPassword) async {
    if (accounts.isEmpty) throw StateError('There are no local accounts to upload.');
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before uploading.');
    final existing = await client.from('encrypted_vaults').select('revision').eq('user_id', user.id).maybeSingle();
    if (existing != null) throw StateError('Cloud vault already exists. Upload blocked to prevent overwriting another device.');
    final bytes = await BackupCodec.export(accounts, masterPassword);
    final envelope = jsonDecode(utf8.decode(bytes));
    await client.from('encrypted_vaults').insert({
      'user_id': user.id,
      'envelope': envelope,
      'revision': 1,
    });
  }

  static Future<List<AuthAccount>> download(String masterPassword) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before restoring.');
    final row = await client.from('encrypted_vaults').select('envelope').eq('user_id', user.id).maybeSingle();
    if (row == null) throw StateError('No encrypted cloud vault found for this account.');
    final raw = utf8.encode(jsonEncode(row['envelope']));
    return BackupCodec.restore(Uint8List.fromList(raw), masterPassword);
  }
  /// Updates only the revision we read; refuses to overwrite changes from another device.
  static Future<void> updateEncrypted(List<AuthAccount> accounts, String masterPassword) async {
    if (accounts.isEmpty) throw StateError('No local accounts to back up.');
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in to upload.');
    final row = await client.from('encrypted_vaults').select('revision,envelope').eq('user_id', user.id).maybeSingle();
    if (row == null) {
      await firstUpload(accounts, masterPassword);
      return;
    }
    // Validate the existing password and retain accounts present only in cloud.
    final old = await BackupCodec.restore(
      Uint8List.fromList(utf8.encode(jsonEncode(row['envelope']))), masterPassword);
    final merged = <String, AuthAccount>{};
    String key(AuthAccount a) => '${a.issuer.toLowerCase()}|${a.name.toLowerCase()}|${a.secret.replaceAll(' ', '').toUpperCase()}';
    for (final a in old) { merged[key(a)] = a; }
    for (final a in accounts) { merged[key(a)] = a; }
    final bytes = await BackupCodec.export(merged.values.toList(), masterPassword);
    final revision = row['revision'] as int;
    final result = await client.rpc('update_encrypted_vault', params: {
      'expected_revision': revision, 'new_envelope': jsonDecode(utf8.decode(bytes)),
    });
    if (result == null) throw StateError('Cloud vault changed on another device. Retry later; no data was overwritten.');
  }

}
