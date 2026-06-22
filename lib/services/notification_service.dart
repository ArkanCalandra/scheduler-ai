import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open');

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        macOS: iosSettings,
        linux: linuxSettings,
      ),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    // Request ignore battery optimizations to keep alarms alive when app is closed/terminated
    try {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      debugPrint('Battery optimization permission request failed: $e');
    }

    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  static Future<void> scheduleNotification({
    required int id,
    int? preId,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required int preAlarmMinutes,
  }) async {
    final now = DateTime.now();
    final delay = scheduledTime.difference(now);
    if (delay.isNegative) return;

    // Schedule main alarm
    await _scheduleSingle(id, title, body, scheduledTime);

    // Schedule pre-alarm
    if (preAlarmMinutes > 0 && preId != null) {
      final preTime = scheduledTime.subtract(Duration(minutes: preAlarmMinutes));
      if (preTime.isAfter(now)) {
        await _scheduleSingle(preId, '⏳ Segera: $title', body, preTime);
      }
    }
  }

  static Future<void> _scheduleSingle(int id, String title, String body, DateTime scheduledTime) async {

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'scheduler_channel',
            'Scheduler Reminders',
            channelDescription: 'Reminder dari Scheduler',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Notif error with exact: $e. Falling back to inexact...');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          tz.TZDateTime.from(scheduledTime, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'scheduler_channel',
              'Scheduler Reminders',
              channelDescription: 'Reminder dari Scheduler',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
            ),
            iOS: DarwinNotificationDetails(),
            macOS: DarwinNotificationDetails(),
            linux: LinuxNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (innerErr) {
        debugPrint('Fallback to inexact failed: $innerErr');
      }
    }
  }

  static Future<void> cancel(int id) async {
    try { await _plugin.cancel(id); } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try { await _plugin.cancelAll(); } catch (_) {}
  }
}
