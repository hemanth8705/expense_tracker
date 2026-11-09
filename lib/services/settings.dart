import 'package:shared_preferences/shared_preferences.dart';

import '../core/period.dart';

enum WidgetPeriod { thisMonth, lastMonth, thisWeek, specificMonth }

extension WidgetPeriodLabel on WidgetPeriod {
  String get label => switch (this) {
        WidgetPeriod.thisMonth => 'This month',
        WidgetPeriod.lastMonth => 'Last month',
        WidgetPeriod.thisWeek => 'This week',
        WidgetPeriod.specificMonth => 'A specific month',
      };
}

/// Small key-value preferences (not transaction data).
class Settings {
  Settings(this._p);
  final SharedPreferences _p;

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  bool get onboarded => _p.getBool('onboarded') ?? false;
  set onboarded(bool v) => _p.setBool('onboarded', v);

  /// Time (ms) the last successful SMS scan started.
  int? get lastScanMs => _p.getInt('last_scan_ms');
  set lastScanMs(int? v) => v == null ? _p.remove('last_scan_ms') : _p.setInt('last_scan_ms', v);

  bool get reminderEnabled => _p.getBool('reminder_enabled') ?? true;
  set reminderEnabled(bool v) => _p.setBool('reminder_enabled', v);
  int get reminderHour => _p.getInt('reminder_hour') ?? 21;
  int get reminderMinute => _p.getInt('reminder_minute') ?? 0;
  void setReminderTime(int h, int m) {
    _p.setInt('reminder_hour', h);
    _p.setInt('reminder_minute', m);
  }

  WidgetPeriod get widgetPeriod => WidgetPeriod.values.firstWhere(
        (v) => v.name == _p.getString('w_period'),
        orElse: () => WidgetPeriod.thisMonth,
      );
  set widgetPeriod(WidgetPeriod v) => _p.setString('w_period', v.name);

  /// Used when [widgetPeriod] is specificMonth, stored as yyyy*12+(m-1).
  DateTime get widgetMonth {
    final v = _p.getInt('w_month');
    final now = DateTime.now();
    if (v == null) return DateTime(now.year, now.month);
    return DateTime(v ~/ 12, v % 12 + 1);
  }

  set widgetMonth(DateTime d) => _p.setInt('w_month', d.year * 12 + d.month - 1);

  /// null = all transactions, -1 = untagged only, otherwise a tag id.
  int? get widgetTagId => _p.getInt('w_tag');
  set widgetTagId(int? v) => v == null ? _p.remove('w_tag') : _p.setInt('w_tag', v);

  bool get widgetShowDebit => _p.getBool('w_show_debit') ?? true;
  set widgetShowDebit(bool v) => _p.setBool('w_show_debit', v);
  bool get widgetShowCredit => _p.getBool('w_show_credit') ?? true;
  set widgetShowCredit(bool v) => _p.setBool('w_show_credit', v);
  bool get widgetShowNet => _p.getBool('w_show_net') ?? true;
  set widgetShowNet(bool v) => _p.setBool('w_show_net', v);

  Period resolveWidgetPeriod(DateTime now) => switch (widgetPeriod) {
        WidgetPeriod.thisMonth => Period.thisMonth(now),
        WidgetPeriod.lastMonth => Period.lastMonth(now),
        WidgetPeriod.thisWeek => Period.week(now),
        WidgetPeriod.specificMonth => Period.month(widgetMonth.year, widgetMonth.month),
      };
}
