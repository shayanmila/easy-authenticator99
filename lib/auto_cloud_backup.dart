import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backup_schedule.dart';
import 'cloud_account.dart';
import 'cloud_vault.dart';
import 'totp.dart';

/// Foreground-only: one timer until due; no background task or server cron.
class AutoCloudBackup {
  static final instance = AutoCloudBackup._();
  AutoCloudBackup._();
  static const secure = FlutterSecureStorage();
  static const secretKey = 'easy_auth_auto_backup_master_v1';
  Timer? _timer;
  Future<List<AuthAccount>> Function()? _accounts;
  bool _running = false;
  String status = 'Disabled';
  BackupSchedule? schedule;
  String? _owner;
  void Function()? onChange;

  Future<void> initialize(Future<List<AuthAccount>> Function() accounts) async {
    _accounts = accounts;
    await refresh();
  }

  Future<void> refresh() async {
    _timer?.cancel();
    if (!CloudAuthConfig.initialized) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) { schedule = null; status = 'Sign in to enable'; onChange?.call(); return; }
    final p = await SharedPreferences.getInstance();
    _owner = user.id;
    if (p.getString('easy_auth_auto_owner') != user.id || !(p.getBool('easy_auth_auto_enabled') ?? false)) {
      schedule = null; status = 'Disabled'; onChange?.call(); return;
    }
    final name = p.getString('cloud_backup_cadence') ?? 'daily';
    final cadence = BackupCadence.values.firstWhere((x) => x.name == name, orElse: () => BackupCadence.daily);
    final epoch = p.getInt('cloud_backup_next_due');
    if (epoch == null) { status = 'Schedule missing'; onChange?.call(); return; }
    schedule = BackupSchedule(cadence: cadence, nextDue: DateTime.fromMillisecondsSinceEpoch(epoch),
      interval: p.getInt('cloud_backup_interval') ?? 1, hour: p.getInt('cloud_backup_hour') ?? 2,
      minute: p.getInt('cloud_backup_minute') ?? 0, weekday: p.getInt('cloud_backup_weekday') ?? 1,
      specificDate: p.getInt('cloud_backup_once_date') == null ? null : DateTime.fromMillisecondsSinceEpoch(p.getInt('cloud_backup_once_date')!));
    status = 'Scheduled';
    onChange?.call();
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    final s = schedule;
    if (s == null || _running) return;
    final remaining = s.nextDue.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      Future.microtask(runIfDue);
    } else {
      // Dart timers have bounded platform duration; re-arm for distant dates.
      _timer = Timer(remaining > const Duration(days: 1) ? const Duration(days: 1) : remaining, () { runIfDue(); });
    }
  }

  Future<void> enable(BackupSchedule newSchedule, String master) async {
    if (master.length < 12) throw StateError('Master password must be at least 12 characters.');
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw StateError('Sign in first.');
    // Confirm password works on existing vault before storing credential.
    await CloudVaultService.download(master);
    await secure.write(key: secretKey, value: master);
    final p = await SharedPreferences.getInstance();
    await newSchedule.save();
    await p.setString('easy_auth_auto_owner', user.id);
    await p.setBool('easy_auth_auto_enabled', true);
    await refresh();
  }

  Future<void> disable() async {
    _timer?.cancel();
    schedule = null;
    await secure.delete(key: secretKey);
    final p = await SharedPreferences.getInstance();
    await p.setBool('easy_auth_auto_enabled', false);
    status = 'Disabled';
    onChange?.call();
  }

  Future<void> runIfDue() async {
    if (_running || schedule == null) return;
    if (DateTime.now().isBefore(schedule!.nextDue)) { _arm(); return; }
    if (!CloudAuthConfig.initialized || Supabase.instance.client.auth.currentUser?.id != _owner) {
      status = 'Sign in to resume backups'; onChange?.call(); return;
    }
    _running = true;
    _timer?.cancel();
    status = 'Backing up...'; onChange?.call();
    try {
      final master = await secure.read(key: secretKey);
      if (master == null) throw StateError('Secure backup credential missing. Re-enable backup.');
      final accounts = await _accounts?.call() ?? <AuthAccount>[];
      await CloudVaultService.updateEncrypted(accounts, master);
      final s = schedule!;
      final p = await SharedPreferences.getInstance();
      await p.setString('easy_auth_auto_last_success', DateTime.now().toIso8601String());
      if (s.cadence == BackupCadence.once) {
        await disable();
        status = 'One-time backup completed';
      } else {
        // Next interval starts after success; missed intervals are not replayed.
        final next = BackupSchedule(cadence: s.cadence,
          nextDue: BackupSchedule.calculateNext(s.cadence, DateTime.now(),
            interval: s.interval, hour: s.hour, minute: s.minute, weekday: s.weekday),
          interval: s.interval, hour: s.hour, minute: s.minute, weekday: s.weekday);
        schedule = next;
        await next.save();
        status = 'Backup successful';
      }
    } catch (e) {
      status = 'Backup failed: $e';
      // Retry in 5 minutes without advancing the original due date.
      _running = false;
      onChange?.call();
      _timer = Timer(const Duration(minutes: 5), runIfDue);
      return;
    }
    _running = false;
    onChange?.call();
    _arm();
  }

  void onResume() { runIfDue(); }
  void disposeTimer() { _timer?.cancel(); }
}
