import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight foreground-only schedule calculation.
/// No background service, wake lock, polling loop or backend cron.
enum BackupCadence { minutes, hours, days, daily, weekly, once }

class BackupSchedule {
  final BackupCadence cadence;
  final int interval;
  final int hour;
  final int minute;
  final int weekday;
  final DateTime? specificDate;
  final DateTime nextDue;
  const BackupSchedule({
    required this.cadence, required this.nextDue, this.interval = 1,
    this.hour = 2, this.minute = 0, this.weekday = DateTime.monday,
    this.specificDate,
  });

  static DateTime calculateNext(BackupCadence cadence, DateTime from, {
    int interval = 1, int hour = 2, int minute = 0,
    int weekday = DateTime.monday, DateTime? specificDate,
  }) {
    if (interval < 1 || interval > 10000) throw ArgumentError('Invalid interval');
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) throw ArgumentError('Invalid time');
    if (weekday < 1 || weekday > 7) throw ArgumentError('Invalid weekday');
    switch (cadence) {
      case BackupCadence.minutes: return from.add(Duration(minutes: interval));
      case BackupCadence.hours: return from.add(Duration(hours: interval));
      case BackupCadence.days: return from.add(Duration(days: interval));
      case BackupCadence.daily:
        var date = DateTime(from.year, from.month, from.day, hour, minute);
        if (!date.isAfter(from)) date = DateTime(from.year, from.month, from.day + 1, hour, minute);
        return date;
      case BackupCadence.weekly:
        var date = DateTime(from.year, from.month, from.day + (weekday - from.weekday + 7) % 7, hour, minute);
        if (!date.isAfter(from)) date = DateTime(date.year, date.month, date.day + 7, hour, minute);
        return date;
      case BackupCadence.once:
        if (specificDate == null || !specificDate.isAfter(from)) throw ArgumentError('Choose a future date');
        return specificDate;
    }
  }

  bool isDue(DateTime now) => !now.isBefore(nextDue);

  /// Save metadata only. Never store vault passwords in preferences.
  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('cloud_backup_cadence', cadence.name);
    await p.setInt('cloud_backup_interval', interval);
    await p.setInt('cloud_backup_hour', hour);
    await p.setInt('cloud_backup_minute', minute);
    await p.setInt('cloud_backup_weekday', weekday);
    await p.setInt('cloud_backup_next_due', nextDue.millisecondsSinceEpoch);
    if (specificDate != null) await p.setInt('cloud_backup_once_date', specificDate!.millisecondsSinceEpoch);
  }
}
