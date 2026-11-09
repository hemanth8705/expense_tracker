import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily "time to refresh" reminder with a Refresh action button.
/// Tapping the button (or the notification) opens the app and refreshes.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _dailyId = 1;
  static const refreshAction = 'refresh';

  /// Incremented whenever the user asks to refresh from a notification.
  static final refreshRequests = ValueNotifier<int>(0);

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) => refreshRequests.value++,
    );

    // App was cold-started from the notification.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      refreshRequests.value++;
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? true;

  static Future<void> scheduleDaily(int hour, int minute) async {
    await _plugin.cancel(id: _dailyId);
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      id: _dailyId,
      title: 'Time to refresh your expenses',
      body: 'Import today\'s bank SMS and tag them.',
      scheduledDate: at,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_refresh',
          'Daily refresh reminder',
          channelDescription: 'Reminds you to import new bank SMS',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          actions: [
            AndroidNotificationAction(
              refreshAction,
              'Refresh',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      // Inexact is fine for a daily nudge and needs no exact-alarm permission.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: refreshAction,
    );
  }

  static Future<void> cancelDaily() => _plugin.cancel(id: _dailyId);
}
