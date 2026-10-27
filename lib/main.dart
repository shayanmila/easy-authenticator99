import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'backup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'totp.dart';
import 'migration.dart';
import 'cloud_account.dart';
import 'auto_cloud_backup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (CloudAuthConfig.isConfigured) {
    try {
      await Supabase.initialize(url: CloudAuthConfig.url, anonKey: CloudAuthConfig.publishableKey);
      CloudAuthConfig.initialized = true;
    } catch (e) {
      debugPrint('Cloud sign-in unavailable; continuing in offline mode: $e');
    }
  }
  runApp(const EasyAuthenticator());
}

class EasyAuthenticator extends StatefulWidget {
  const EasyAuthenticator({super.key});
  @override State<EasyAuthenticator> createState() => _EasyAuthenticatorState();
}
class _EasyAuthenticatorState extends State<EasyAuthenticator> {
  ThemeMode mode = ThemeMode.system;
  double textScale = 1.0;
  String fontStyle = 'Default';
  @override void initState() { super.initState(); SharedPreferences.getInstance().then((p) { if (mounted) setState(() { mode = ThemeMode.values[p.getInt('easy_auth_theme')?.clamp(0,2) ?? 0]; textScale = (p.getDouble('easy_auth_text_scale_v1') ?? 1.0).clamp(0.85, 1.4); fontStyle = p.getString('easy_auth_font_style_v1') ?? 'Default'; }); }); }
  Future<void> setMode(ThemeMode next) async { setState(() => mode = next); final p = await SharedPreferences.getInstance(); await p.setInt('easy_auth_theme', next.index); }
  Future<void> setTextScale(double value) async { setState(() => textScale = value); final p = await SharedPreferences.getInstance(); await p.setDouble('easy_auth_text_scale_v1', value); }
  Future<void> setFontStyle(String value) async { setState(() => fontStyle = value); final p = await SharedPreferences.getInstance(); await p.setString('easy_auth_font_style_v1', value); }
  @override Widget build(BuildContext context) => MaterialApp(title: 'Easy Authenticator', debugShowCheckedModeBanner: false, theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5066D9)), useMaterial3: true, fontFamily: fontStyle == 'Serif' ? 'serif' : fontStyle == 'Mono' ? 'monospace' : null), darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B9AFF), brightness: Brightness.dark), useMaterial3: true, fontFamily: fontStyle == 'Serif' ? 'serif' : fontStyle == 'Mono' ? 'monospace' : null), themeMode: mode, builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child ?? const SizedBox.shrink()), home: HomePage(mode: mode, onModeChanged: setMode, textScale: textScale, fontStyle: fontStyle, onTextScaleChanged: setTextScale, onFontStyleChanged: setFontStyle));
}

class HomePage extends StatefulWidget { final ThemeMode mode; final ValueChanged<ThemeMode> onModeChanged; final double textScale; final String fontStyle; final ValueChanged<double> onTextScaleChanged; final ValueChanged<String> onFontStyleChanged; const HomePage({super.key, required this.mode, required this.onModeChanged, required this.textScale, required this.fontStyle, required this.onTextScaleChanged, required this.onFontStyleChanged}); @override State<HomePage> createState() => _HomePageState(); }
class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const storage = FlutterSecureStorage();
  final List<AuthAccount> accounts = [];

  final LocalAuthentication localAuth = LocalAuthentication();
  bool protectionLoaded = false, pinEnabled = false, locked = true, biometricEnabled = false;
  int autoLockSeconds = 30;
  DateTime? backgroundAt;
  String? pinSalt, pinHash;
  String hashPin(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();
  Future<void> loadProtection() async {
    try {
      pinSalt = await storage.read(key: 'easy_auth_pin_salt_v1');
      pinHash = await storage.read(key: 'easy_auth_pin_hash_v1');
      pinEnabled = pinSalt != null && pinHash != null;
      final prefs = await SharedPreferences.getInstance();
      biometricEnabled = prefs.getBool('easy_auth_biometric_v1') ?? false;
      autoLockSeconds = prefs.getInt('easy_auth_auto_lock_v1') ?? 30;
      locked = pinEnabled;
    } catch (_) { locked = true; }
    protectionLoaded = true;
    if(mounted) setState(() {});
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      backgroundAt ??= DateTime.now();
      if(pinEnabled && autoLockSeconds == 0 && mounted) setState(() => locked = true);
    } else if(state == AppLifecycleState.resumed) {
      if(pinEnabled && backgroundAt != null && DateTime.now().difference(backgroundAt!).inSeconds >= autoLockSeconds) {
        setState(() => locked = true);
      }
      backgroundAt = null;
      AutoCloudBackup.instance.refresh();
    }
  }
  Future<String?> pinDialog(String title, {bool confirm = false}) async {
    final a = TextEditingController(), b = TextEditingController();
    try {
      return await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: Text(title), content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: a, obscureText: true, keyboardType: TextInputType.number, maxLength: 12, decoration: const InputDecoration(labelText: 'PIN (6-12 digits)')),
          if(confirm) TextField(controller: b, obscureText: true, keyboardType: TextInputType.number, maxLength: 12, decoration: const InputDecoration(labelText: 'Confirm PIN')),
        ]), actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if(a.text.length < 6 || a.text.length > 12 || !RegExp(r'^[0-9]+').hasMatch(a.text) || (confirm && a.text != b.text)) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('PIN must be 6-12 digits and match confirmation.')));
              return;
            }
            Navigator.pop(ctx, a.text);
          }, child: const Text('Continue'))
        ]));
    } finally { a.dispose(); b.dispose(); }
  }
  Future<bool> verifyPin() async {
    final pin = await pinDialog('Enter app PIN');
    if(pin == null) return false;
    final valid = pinSalt != null && pinHash != null && hashPin(pin, pinSalt!) == pinHash;
    if(!valid) _message('Incorrect PIN');
    return valid;
  }
  Future<void> unlockPin() async { if(await verifyPin() && mounted) setState(() => locked = false); }
  Future<void> unlockBiometric() async {
    try {
      final ok = await localAuth.authenticate(localizedReason: 'Unlock Easy Authenticator',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true));
      if(ok && mounted) setState(() => locked = false);
    } catch(e) { _message('Biometric unavailable: $e'); }
  }
  Future<void> configurePin() async {
    if(pinEnabled && !await verifyPin()) return;
    final pin = await pinDialog(pinEnabled ? 'Change PIN' : 'Create PIN', confirm: true);
    if(pin == null) return;
    final rng = Random.secure();
    final salt = base64UrlEncode(List<int>.generate(32, (_) => rng.nextInt(256)));
    final hash = hashPin(pin, salt);
    await storage.write(key: 'easy_auth_pin_salt_v1', value: salt);
    await storage.write(key: 'easy_auth_pin_hash_v1', value: hash);
    if(mounted) setState(() { pinSalt = salt; pinHash = hash; pinEnabled = true; locked = false; });
  }
  Future<void> disablePin() async {
    if(!await verifyPin()) return;
    await storage.delete(key: 'easy_auth_pin_hash_v1');
    await storage.delete(key: 'easy_auth_pin_salt_v1');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('easy_auth_biometric_v1', false);
    if(mounted) setState(() { pinEnabled = false; biometricEnabled = false; locked = false; pinSalt = null; pinHash = null; });
  }
  Future<void> configureAutoLock(int seconds) async {
    if(!pinEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('easy_auth_auto_lock_v1', seconds);
    if(mounted) setState(() => autoLockSeconds = seconds);
  }
  Future<void> configureBiometric(bool enabled) async {
    if(enabled) {
      if(!pinEnabled) { _message('Set a PIN first'); return; }
      try {
        if(!await localAuth.canCheckBiometrics || (await localAuth.getAvailableBiometrics()).isEmpty) {
          _message('No enrolled biometrics available'); return;
        }
      } catch(e) { _message('Biometric check failed: $e'); return; }
    }
    if(pinEnabled && !await verifyPin()) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('easy_auth_biometric_v1', enabled);
    if(mounted) setState(() => biometricEnabled = enabled);
  }
  Widget lockScreen() => Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.lock, size: 72), const SizedBox(height: 18),
    const Text('Easy Authenticator is locked'), const SizedBox(height: 18),
    FilledButton.icon(onPressed: unlockPin, icon: const Icon(Icons.pin), label: const Text('Unlock with PIN')),
    if(biometricEnabled) OutlinedButton.icon(onPressed: unlockBiometric, icon: const Icon(Icons.fingerprint), label: const Text('Biometric unlock')),
  ])));

  Timer? timer;
  DateTime now = DateTime.now();
  String query = '';
  bool loading = true;
  int section = 0;
  bool hideCodes = false;
  final Map<int, List<AuthAccount>> pendingTransfer = {};
  int? transferId;
  int? transferSize;
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); loadProtection(); _load(); AutoCloudBackup.instance.initialize(() async => List<AuthAccount>.of(accounts)); timer = Timer.periodic(const Duration(seconds: 1), (_) { if(mounted && !locked && section == 0 && !loading) setState(() => now = DateTime.now()); }); }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); timer?.cancel(); AutoCloudBackup.instance.disposeTimer(); super.dispose(); }
  Future<void> _load() async {
    try { final value = await storage.read(key: 'easy_auth_accounts_v1'); if(value != null) accounts.addAll(deserializeAccounts(value)); }
    catch (e) { if(mounted) _message('Unable to read encrypted storage: $e'); }
    if(mounted) setState(() => loading = false); AutoCloudBackup.instance.onResume();
  }
  Future<void> _save() async { await storage.write(key: 'easy_auth_accounts_v1', value: serializeAccounts(accounts)); if(mounted) setState(() {}); }
  void _message(String text) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }
  Future<void> _add(AuthAccount account) async { try { decodeBase32(account.secret); final next = [...accounts, account]; await storage.write(key: 'easy_auth_accounts_v1', value: serializeAccounts(next)); accounts.add(account); if(mounted) setState(() {}); _message('Account added'); } catch(e) { _message('Unable to save account: $e'); } }
  Future<void> _delete(AuthAccount a) async {
    final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Delete account?'), content: Text('Remove ${a.issuer} ${a.name}? This cannot be undone without the original setup secret.'), actions: [TextButton(onPressed: () => Navigator.pop(c,false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c,true), child: const Text('Delete'))]));
    if(confirmed == true) { try { final next = accounts.where((e) => e.id != a.id).toList(); await storage.write(key: 'easy_auth_accounts_v1', value: serializeAccounts(next)); accounts..clear()..addAll(next); if(mounted) setState(() {}); } catch(e) { _message('Unable to save deletion: $e'); } }
  }
  Future<void> _addManual() async {
    final issuer = TextEditingController(), name = TextEditingController(), secret = TextEditingController();
    final result = await showDialog<AuthAccount>(context: context, builder: (ctx) => AlertDialog(title: const Text('Add account manually'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: issuer, decoration: const InputDecoration(labelText: 'Service / issuer')), TextField(controller: name, decoration: const InputDecoration(labelText: 'Account name')), TextField(controller: secret, decoration: const InputDecoration(labelText: 'Base32 setup key'), autocorrect: false, enableSuggestions: false)])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () { try { decodeBase32(secret.text); Navigator.pop(ctx, AuthAccount(id: DateTime.now().microsecondsSinceEpoch.toString(), issuer: issuer.text.trim(), name: name.text.trim().isEmpty ? 'Account' : name.text.trim(), secret: secret.text.trim())); } catch (_) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Invalid Base32 key'))); } }, child: const Text('Save'))]));
    issuer.dispose(); name.dispose(); secret.dispose(); if(result != null) await _add(result);
  }
  Future<void> _importTransfer(String raw) async {
    final batch = parseGoogleMigration(raw);
    if (transferId != null && (transferId != batch.batchId || transferSize != batch.size)) {
      pendingTransfer.clear();
    }
    transferId = batch.batchId; transferSize = batch.size;
    pendingTransfer[batch.index] = batch.accounts;
    if (pendingTransfer.length < batch.size) {
      _message('Transfer QR ${batch.index + 1}/${batch.size} captured. Scan the remaining QR codes.');
      return;
    }
    final incoming = <AuthAccount>[];
    for (var i = 0; i < batch.size; i++) {
      if (!pendingTransfer.containsKey(i)) return;
      incoming.addAll(pendingTransfer[i]!);
    }
    final existing = accounts.map((a) => '${a.issuer.toLowerCase()}|${a.name.toLowerCase()}|${a.secret.replaceAll(' ', '').toUpperCase()}').toSet();
    final unique = <AuthAccount>[];
    for (final a in incoming) {
      final key = '${a.issuer.toLowerCase()}|${a.name.toLowerCase()}|${a.secret.replaceAll(' ', '').toUpperCase()}';
      if (existing.add(key)) unique.add(a);
    }
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Import Google Authenticator accounts?'),
      content: Text('${incoming.length} accounts found across ${batch.size} QR code(s).\n${incoming.length - unique.length} duplicate(s) skipped.\n${unique.length} new account(s) will be added. Existing accounts will remain unchanged.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import'))],
    ));
    if (confirmed == true && unique.isNotEmpty) {
      try {
        final next = [...accounts, ...unique];
        await storage.write(key: 'easy_auth_accounts_v1', value: serializeAccounts(next));
        accounts..clear()..addAll(next);
        if (mounted) setState(() {});
        _message('${unique.length} accounts imported');
      } catch (_) { _message('Import failed. Existing accounts were not changed.'); }
    }
    pendingTransfer.clear(); transferId = null; transferSize = null;
  }
  Future<void> _scan() async {
    if(defaultTargetPlatform != TargetPlatform.android) { _message('QR camera scanning is currently Android-only. Use manual entry on Windows.'); return; }
    final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if(result != null) { try { if(result.startsWith('otpauth-migration://')) { await _importTransfer(result); } else { await _add(parseOtpAuth(result)); } } catch(e) { _message('Invalid QR code: $e'); } }
  }
  Future<void> _rename(AuthAccount a) async {
    final issuer = TextEditingController(text: a.issuer);
    final name = TextEditingController(text: a.name);
    final result = await showDialog<AuthAccount>(context: context, builder: (ctx) => AlertDialog(title: const Text('Edit account'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: issuer, decoration: const InputDecoration(labelText: 'Service')), TextField(controller: name, decoration: const InputDecoration(labelText: 'Account'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, AuthAccount(id: a.id, issuer: issuer.text.trim(), name: name.text.trim(), secret: a.secret, digits: a.digits, period: a.period, algorithm: a.algorithm)), child: const Text('Save'))]));
    if (result != null) {
      try { final next = accounts.map((e) => e.id == a.id ? result : e).toList(); await storage.write(key: 'easy_auth_accounts_v1', value: serializeAccounts(next)); accounts..clear()..addAll(next); if(mounted) setState(() {}); }
      catch (_) { _message('Unable to save changes'); }
    }
    issuer.dispose(); name.dispose();
  }
  Future<String?> _backupPassword({required bool confirm}) async {
    final first = TextEditingController(), second = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(confirm ? 'Encrypt backup' : 'Unlock backup'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(confirm ? 'Choose a strong password (12+ characters). Without it the backup cannot be recovered.' : 'Enter the password used when exporting this backup.'),
        TextField(controller: first, obscureText: true, decoration: const InputDecoration(labelText: 'Backup password')),
        if(confirm) TextField(controller: second, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if(first.text.isEmpty || (confirm && (first.text.length < 12 || first.text != second.text))) {
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Password must match and contain at least 12 characters.'))); return;
          }
          Navigator.pop(ctx, first.text);
        }, child: Text(confirm ? 'Continue' : 'Unlock'))],
    ));
    first.dispose(); second.dispose();
    return result;
  }
  Future<void> _exportBackup() async {
    if(accounts.isEmpty) { _message('No accounts to back up'); return; }
    final password = await _backupPassword(confirm: true);
    if(password == null) return;
    try {
      final bytes = await BackupCodec.export(accounts, password);
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save encrypted backup',
        fileName: 'easy-auth-backup.eauth',
        type: FileType.custom, allowedExtensions: ['eauth'],
        bytes: bytes,
      );
      if(destination == null) { _message('Backup save cancelled'); return; }
      if(Platform.isWindows) {
        final file = File(destination);
        await file.writeAsBytes(bytes, flush: true);
        if(!await file.exists() || await file.length() != bytes.length) {
          throw const FileSystemException('Backup file could not be verified');
        }
        final check = await file.readAsBytes();
        if(!listEquals(check, bytes)) {
          throw const FileSystemException('Backup verification failed');
        }
      }
      _message('Encrypted backup saved: $destination');
    } catch(e) { _message('Backup export failed: $e'); }
  }
  Future<void> _restoreBackup() async {
    try {
      // Android's document picker may reject custom extensions without a MIME mapping.
      // Use the system's all-files picker and validate the selected backup ourselves.
      final selection = await FilePicker.platform.pickFiles(
        type: Platform.isAndroid ? FileType.any : FileType.custom,
        allowedExtensions: Platform.isAndroid ? null : ['eauth'],
        withData: true,
      );
      if(selection == null) return;
      final selected = selection.files.single;
      if(!selected.name.toLowerCase().endsWith('.eauth')) {
        _message('Select an Easy Authenticator .eauth backup file');
        return;
      }
      Uint8List? data = selected.bytes;
      if(data == null && selected.path != null) {
        data = await File(selected.path!).readAsBytes();
      }
      if(data == null || data.isEmpty) {
        _message('Unable to read selected backup file');
        return;
      }
      final password = await _backupPassword(confirm: false);
      if(password == null) return;
      final imported = await BackupCodec.restore(data, password);
      if(!mounted) return;
      final seen = accounts.map((a) => '${a.issuer.toLowerCase()}|${a.name.toLowerCase()}|${a.secret.replaceAll(' ', '').toUpperCase()}').toSet();
      final unique = <AuthAccount>[];
      for(final a in imported) {
        final signature = '${a.issuer.toLowerCase()}|${a.name.toLowerCase()}|${a.secret.replaceAll(' ', '').toUpperCase()}';
        if(seen.add(signature)) unique.add(a);
      }
      final proceed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Restore accounts?'),
        content: Text('${imported.length} account(s) in backup. ${unique.length} new, ${imported.length - unique.length} duplicate(s). Existing accounts will NOT be deleted.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Restore'))],
      ));
      if(proceed != true || unique.isEmpty) return;
      final usedIds = accounts.map((a) => a.id).toSet();
      final restored = <AuthAccount>[];
      for(final a in unique) {
        var id = a.id;
        if(!usedIds.add(id)) { id = '${DateTime.now().microsecondsSinceEpoch}-${restored.length}'; usedIds.add(id); }
        restored.add(AuthAccount(id: id, issuer: a.issuer, name: a.name, secret: a.secret, digits: a.digits, period: a.period, algorithm: a.algorithm));
      }
      final next = [...accounts, ...restored];
      await storage.write(key: 'easy_auth_accounts_v1', value: serializeAccounts(next));
      accounts..clear()..addAll(next);
      if(mounted) setState(() {});
      _message('${restored.length} account(s) restored');
    } catch (e) { _message('Restore failed: $e. Existing accounts were not changed.'); }
  }
  Widget _navigation(bool wide) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Padding(padding: EdgeInsets.all(20), child: Row(children: [Icon(Icons.shield_rounded, color: Color(0xFF3565ED), size: 32), SizedBox(width: 12), Expanded(child: Text('Easy Authenticator', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))])),
    for (final item in [(Icons.account_circle_outlined,'Accounts'),(Icons.lock_outline,'Protection'),(Icons.backup_outlined,'Backup'),(Icons.info_outline,'About'),(Icons.settings_outlined,'Settings'),(Icons.cloud_outlined,'Cloud Account')])
      Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: ListTile(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), selected: section == [(Icons.account_circle_outlined,'Accounts'),(Icons.lock_outline,'Protection'),(Icons.backup_outlined,'Backup'),(Icons.info_outline,'About'),(Icons.settings_outlined,'Settings'),(Icons.cloud_outlined,'Cloud Account')].indexOf(item), selectedTileColor: Theme.of(context).colorScheme.primaryContainer, leading: Icon(item.$1), title: Text(item.$2), onTap: () { setState(() => section = [(Icons.account_circle_outlined,'Accounts'),(Icons.lock_outline,'Protection'),(Icons.backup_outlined,'Backup'),(Icons.info_outline,'About'),(Icons.settings_outlined,'Settings'),(Icons.cloud_outlined,'Cloud Account')].indexOf(item)); if (!wide) Navigator.maybePop(context); })),
    const Spacer(), Padding(padding: const EdgeInsets.all(18), child: Text('OFFLINE • LOCAL STORAGE', style: Theme.of(context).textTheme.labelSmall))
  ]);
  Future<void> openLegalPage(String path) async {
    final uri = Uri.https('masoomdev-website.vercel.app', '/apps/easy-authenticator/$path');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _message('Could not open the website');
  }
  Future<int> _importCloudAccounts(List<AuthAccount> incoming) async {
    final seen = accounts.map((a) => '${a.issuer.toLowerCase()}|${a.name.toLowerCase()}|${a.secret.replaceAll(' ', '').toUpperCase()}').toSet();
    final unique = <AuthAccount>[];
    for (final a in incoming) {
      final signature = '${a.issuer.toLowerCase()}|${a.name.toLowerCase()}|${a.secret.replaceAll(' ', '').toUpperCase()}';
      if (seen.add(signature)) unique.add(a);
    }
    if (unique.isEmpty) return 0;
    final next = [...accounts, ...unique];
    await storage.write(key: 'easy_auth_accounts_v1', value: serializeAccounts(next));
    accounts..clear()..addAll(next);
    if (mounted) setState(() {});
    return unique.length;
  }
  Widget _infoPage() {
    if (section == 5) return CloudAccountPage(localAccounts: accounts, importAccounts: _importCloudAccounts);
    if(section == 4) return ListView(padding: const EdgeInsets.all(24), children: [Text('Settings', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 20), const Text('Appearance'), for(final m in ThemeMode.values) RadioListTile<ThemeMode>(title: Text(m.name.toUpperCase()), value: m, groupValue: widget.mode, onChanged: (v) { if(v != null) widget.onModeChanged(v); }), const Divider(height: 28), const Text('Text size'), Slider(value: widget.textScale, min: 0.85, max: 1.4, divisions: 11, label: '${(widget.textScale * 100).round()}%', onChanged: widget.onTextScaleChanged), Text('Preview • ${(widget.textScale * 100).round()}%'), const SizedBox(height: 12), const Text('Font styling'), for(final style in ['Default', 'Serif', 'Mono']) RadioListTile<String>(title: Text(style), value: style, groupValue: widget.fontStyle, onChanged: (v) { if(v != null) widget.onFontStyleChanged(v); }), const Divider(height: 28), SwitchListTile(title: const Text('Hide codes'), subtitle: const Text('Conceal codes until you reveal them'), value: hideCodes, onChanged: (v) => setState(() => hideCodes = v))]);
    if(section == 1) return ListView(padding: const EdgeInsets.all(20), children: [
      Text('App Protection', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      ListTile(leading: const Icon(Icons.pin), title: Text(pinEnabled ? 'Change PIN' : 'Set PIN'), subtitle: const Text('6–12 digit security PIN'), onTap: configurePin),
      if(pinEnabled) ListTile(leading: const Icon(Icons.lock_open), title: const Text('Disable PIN'), onTap: disablePin),
      SwitchListTile(secondary: const Icon(Icons.fingerprint), title: const Text('Biometric unlock'), subtitle: const Text('Requires enrolled biometrics and PIN'), value: biometricEnabled, onChanged: configureBiometric),
      if(pinEnabled) ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Auto-lock'), subtitle: Text(autoLockSeconds == 0 ? 'Immediately' : 'After $autoLockSeconds seconds'), trailing: DropdownButton<int>(value: [0,15,30,60,300].contains(autoLockSeconds) ? autoLockSeconds : 30, items: const [DropdownMenuItem(value: 0, child: Text('Immediately')), DropdownMenuItem(value: 15, child: Text('15 sec')), DropdownMenuItem(value: 30, child: Text('30 sec')), DropdownMenuItem(value: 60, child: Text('1 min')), DropdownMenuItem(value: 300, child: Text('5 min'))], onChanged: (v) { if(v != null) configureAutoLock(v); })),
    ]);
    if(section == 2) return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Backup & Restore', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      const Text('Protect your accounts with an encrypted, password-protected .eauth file. All encryption happens locally. The password cannot be reset.'),
      const SizedBox(height: 24),
      Card(child: ListTile(leading: const Icon(Icons.file_upload_outlined), title: const Text('Export encrypted backup'), subtitle: Text('Save ${accounts.length} account(s) to a portable file'), trailing: const Icon(Icons.chevron_right), onTap: _exportBackup)),
      Card(child: ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('Restore from backup'), subtitle: const Text('Add accounts without deleting existing ones'), trailing: const Icon(Icons.chevron_right), onTap: _restoreBackup)),
      const SizedBox(height: 18),
      const Text('Important: Keep your original authenticator and recovery codes until you have verified that a backup restores correctly. Never share your backup file and password together.'),
    ]);
    return ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.shield_rounded, size: 64, color: Color(0xFF5066D9)),
      const SizedBox(height: 16),
      Text('Easy Authenticator', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('Android & Windows • Secure TOTP authenticator', textAlign: TextAlign.center),
      const SizedBox(height: 24),
      const Text('An offline two-factor authentication app. Generate time-based one-time passwords (TOTP) for your accounts without an internet connection.'),
      const SizedBox(height: 16),
      const ListTile(leading: Icon(Icons.qr_code_scanner), title: Text('Account import'), subtitle: Text('Standard TOTP QR and Google Authenticator transfer QR codes')),
      const ListTile(leading: Icon(Icons.lock_outline), title: Text('Local protection'), subtitle: Text('Accounts saved in operating-system secure storage')),
      const ListTile(leading: Icon(Icons.backup_outlined), title: Text('Portable backups'), subtitle: Text('Password-encrypted AES-256-GCM export and additive restore')),
      const ListTile(leading: Icon(Icons.cloud_outlined), title: Text('Optional encrypted cloud backup'), subtitle: Text('Cloud account and master password for backup and manual restore across devices')),
      const ListTile(leading: Icon(Icons.person_outline), title: Text('Developed by MasoomDev'), subtitle: Text('Easy Authenticator • com.masoodev.easyauthenticator')),
      const SizedBox(height: 16),
      const Text('App PIN and biometric unlock are available in Protection settings. Cloud backup is optional; restore on another device is manual. Keep independent recovery methods.', textAlign: TextAlign.center),
      const Divider(height: 24),
      ListTile(leading: const Icon(Icons.info_outline), title: const Text('About Easy Authenticator'), onTap: () => openLegalPage('')),
      ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacy Policy'), onTap: () => openLegalPage('privacy/')),
      ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Terms of Use'), onTap: () => openLegalPage('terms/')),
    ]);
  }
  Widget _accountCard(AuthAccount a) {
    final remaining = a.period - (now.millisecondsSinceEpoch ~/ 1000) % a.period;
    final code = totp(a, now: now);
    final label = hideCodes ? '••• •••' : (code.length == 6 ? '${code.substring(0,3)} ${code.substring(3)}' : '${code.substring(0,4)} ${code.substring(4)}');
    return Card(clipBehavior: Clip.antiAlias, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Text((a.issuer.isNotEmpty ? a.issuer : a.name).substring(0,1).toUpperCase())), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.issuer.isEmpty ? 'Account' : a.issuer, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)])), PopupMenuButton<String>(tooltip: 'Account options', onSelected: (v) { if(v == 'edit') _rename(a); if(v == 'delete') _delete(a); }, itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit name')), const PopupMenuItem(value: 'delete', child: Text('Delete account'))])]),
      const Spacer(), Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 2)))),
      const Spacer(), Row(children: [SizedBox(width: 26, height: 26, child: CircularProgressIndicator(value: remaining / a.period, strokeWidth: 3)), const SizedBox(width: 8), Text('${remaining}s'), const Spacer(), IconButton(tooltip: hideCodes ? 'Reveal code' : 'Hide code', onPressed: () => setState(() => hideCodes = !hideCodes), icon: Icon(hideCodes ? Icons.visibility : Icons.visibility_off)), IconButton(tooltip: 'Copy code', onPressed: () async { await Clipboard.setData(ClipboardData(text: code)); _message('Code copied'); }, icon: const Icon(Icons.copy_outlined))])
    ])));
  }
  @override Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final content = section != 0 ? _infoPage() : Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(18,18,18,8), child: Row(children: [Expanded(child: TextField(onChanged: (s) => setState(() => query = s), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search accounts...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))))), const SizedBox(width: 10), IconButton(tooltip: 'Add account', onPressed: _addManual, icon: const Icon(Icons.add_circle_outline))])),
      Expanded(child: LayoutBuilder(builder: (ctx, constraints) {
        final normalizedQuery = query.trim().toLowerCase();
        final filtered = normalizedQuery.isEmpty ? List<AuthAccount>.of(accounts) : accounts.where((a) => '${a.issuer} ${a.name}'.toLowerCase().contains(normalizedQuery)).toList();
        if(filtered.isEmpty) return Center(child: Text(accounts.isEmpty ? 'No accounts yet. Add your first 2FA account.' : 'No matching accounts.'));
        final cols = constraints.maxWidth >= 1000 ? 3 : constraints.maxWidth >= 620 ? 2 : 1;
        return GridView.builder(padding: const EdgeInsets.all(14), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 205, crossAxisSpacing: 12, mainAxisSpacing: 12), itemCount: filtered.length, itemBuilder: (context,i) => _accountCard(filtered[i]));
      })),
      Padding(padding: const EdgeInsets.all(14), child: Row(children: [Text('Accounts (${accounts.length})'), const Spacer(), FilledButton.icon(onPressed: () => showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.qr_code_scanner), title: const Text('Scan QR code (Android)'), onTap: () { Navigator.pop(ctx); _scan(); }), ListTile(leading: const Icon(Icons.key), title: const Text('Enter setup key'), onTap: () { Navigator.pop(ctx); _addManual(); })]))), icon: const Icon(Icons.add), label: const Text('Add Account'))]))
    ]);
    if(!protectionLoaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if(locked) return lockScreen();
    return Scaffold(appBar: wide ? null : AppBar(title: const Text('Easy Authenticator')), drawer: wide ? null : Drawer(child: SafeArea(child: _navigation(false))), body: loading ? const Center(child: CircularProgressIndicator()) : Row(children: [if(wide) SizedBox(width: 235, child: _navigation(true)), if(wide) const VerticalDivider(width: 1), Expanded(child: content)]));

  }
}

class ScanPage extends StatefulWidget { const ScanPage({super.key}); @override State<ScanPage> createState() => _ScanPageState(); }
class _ScanPageState extends State<ScanPage> {
  bool scanned = false;
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Scan 2FA QR code')), body: MobileScanner(onDetect: (capture) { if(scanned) return; for(final barcode in capture.barcodes) { final raw = barcode.rawValue; if(raw != null && (raw.startsWith('otpauth://') || raw.startsWith('otpauth-migration://'))) { scanned = true; Navigator.pop(context, raw); return; } } }));
}
