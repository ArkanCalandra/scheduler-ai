import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _preAlarmKey = 'pre_alarm_minutes';
  static const String _userNameKey = 'user_name';
  static const String _aiToneKey = 'ai_tone';

  // Defaults
  static const int defaultPreAlarmMinutes = 5;
  static const String defaultUserName = '';
  static const String defaultAiTone = 'casual';

  static Future<int> getPreAlarmMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_preAlarmKey) ?? defaultPreAlarmMinutes;
  }

  static Future<void> setPreAlarmMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_preAlarmKey, minutes);
  }

  static Future<String> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey) ?? defaultUserName;
  }

  static Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
  }

  static Future<String> getAiTone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_aiToneKey) ?? defaultAiTone;
  }

  static Future<void> setAiTone(String tone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiToneKey, tone);
  }
}
