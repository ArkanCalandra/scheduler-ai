import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';
import 'services/gemini_service.dart';
import 'services/background_service.dart';
import 'services/settings_service.dart';
import 'models/schedule_model.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  // Pakai local timezone dari device langsung
  final now = DateTime.now();
  final offset = now.timeZoneOffset;
  // Cari timezone yang cocok dengan offset device
  final locations = tz.timeZoneDatabase.locations;
  tz.Location? matchedLocation;
  for (final loc in locations.values) {
    final tzNow = tz.TZDateTime.now(loc);
    if (tzNow.timeZoneOffset == offset) {
      matchedLocation = loc;
      break;
    }
  }
  tz.setLocalLocation(matchedLocation ?? tz.getLocation('UTC'));
  await NotificationService.init();
  await DatabaseService.init();
  
  if (!kIsWeb) {
    await BackgroundService.init();
  }

  if (!kIsWeb) {
    final upcoming = await DatabaseService.getUpcoming();
    for (final s in upcoming) {
      NotificationService.scheduleNotification(
        id: s.notificationId,
        preId: s.preNotificationId,
        title: '⏰ ${s.title}',
        body: s.note ?? s.title,
        scheduledTime: s.scheduledTime,
        preAlarmMinutes: s.preAlarmMinutes,
      );
    }
  }

  // Initialize Supabase if environment variables are provided
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      _startSupabaseSync();
    } catch (e) {
      debugPrint('Supabase Init Error: $e');
    }
  }

  GeminiService.init();
  runApp(const VexraApp());
}

void _startSupabaseSync() {
  try {
    Supabase.instance.client
        .from('reminders')
        .stream(primaryKey: ['id'])
        .listen((List<Map<String, dynamic>> data) async {
          for (final row in data) {
            try {
              final id = row['id'] is int 
                  ? row['id'] as int 
                  : int.tryParse(row['id'].toString()) ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
              
              final title = row['title']?.toString() ?? 'Reminder';
              final note = row['note']?.toString();
              final scheduledTimeString = row['scheduled_time']?.toString();
              if (scheduledTimeString == null) continue;
              final scheduledTime = DateTime.parse(scheduledTimeString);
              
              // Cek jika jadwal sudah lewat
              if (scheduledTime.isBefore(DateTime.now())) continue;

              final existingList = await DatabaseService.getAll();
              final exists = existingList.any((e) => e.id == id);
              
              if (!exists) {
                final preMins = await SettingsService.getPreAlarmMinutes();
                final preNotifId = preMins > 0 ? id + 100000 : null;

                final model = ScheduleModel(
                  id: id,
                  title: title,
                  scheduledTime: scheduledTime,
                  note: note,
                  notificationId: id,
                  preAlarmMinutes: preMins,
                  preNotificationId: preNotifId,
                );
                
                await DatabaseService.insert(model);
                await NotificationService.scheduleNotification(
                  id: id,
                  preId: preNotifId,
                  title: '⏰ $title',
                  body: note ?? title,
                  scheduledTime: scheduledTime,
                  preAlarmMinutes: preMins,
                );
                debugPrint('🆕 Supabase Sync: Reminder "$title" synced locally!');
              }
            } catch (err) {
              debugPrint('Supabase Row Sync Error: $err');
            }
          }
        });
  } catch (e) {
    debugPrint('Supabase Stream Sync Error: $e');
  }
}

class VexraApp extends StatelessWidget {
  const VexraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VEXRA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            IgnorePointer(
              child: Center(
                child: Transform.rotate(
                  angle: -0.2, // ~11 degrees rotation
                  child: const Opacity(
                    opacity: 0.15,
                    child: Text(
                      '© VEXRA Tech',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
