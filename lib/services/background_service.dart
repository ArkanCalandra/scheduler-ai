import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Keep alive loop
  Timer.periodic(const Duration(hours: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        flutterLocalNotificationsPlugin.show(
          888,
          'VEXRA',
          'Sistem penjadwalan berjalan di latar belakang.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'scheduler_bg_service',
              'Status Layanan Latar Belakang',
              icon: 'ic_bg_service_small',
              ongoing: true,
              importance: Importance.min,
              priority: Priority.min,
            ),
          ),
        );
      }
    }
  });
}

class BackgroundService {
  static Future<void> init() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'scheduler_bg_service', // id
      'Status Layanan Latar Belakang', // title
      description: 'Menjaga aplikasi tetap hidup di latar belakang.', // description
      importance: Importance.min, // importance set to min to make it completely silent/hidden
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'scheduler_bg_service',
        initialNotificationTitle: 'VEXRA Aktif',
        initialNotificationContent: 'Menjaga alarm dan pengingat tetap hidup.',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
      ),
    );

    await service.startService();
  }
}
