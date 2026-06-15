import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schedule_model.dart';

class DatabaseService {
  static const _key = 'schedules_v2';
  static Future<void> init() async {
    try {
      await _cleanOldSchedules();
    } catch (_) {}
  }

  // Auto-delete jadwal yang udah lewat lebih dari 30 hari
  static Future<void> _cleanOldSchedules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = await getAll();
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final filtered = all.where((s) => s.scheduledTime.isAfter(cutoff)).toList();
      await prefs.setString(_key, jsonEncode(filtered.map((e) => e.toMap()).toList()));
    } catch (_) {}
  }

  static Future<int> insert(ScheduleModel s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await getAll();
      list.add(s);
      await prefs.setString(_key, jsonEncode(list.map((e) => e.toMap()).toList()));
    } catch (_) {}
    return s.id;
  }

  static Future<List<ScheduleModel>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final now = DateTime.now();
      return decoded
          .map((e) {
            try {
              return ScheduleModel.fromMap(Map<String, dynamic>.from(e));
            } catch (_) {
              return null;
            }
          })
          .whereType<ScheduleModel>()
          .toList()
        ..sort((a, b) {
          final aPast = a.scheduledTime.isBefore(now);
          final bPast = b.scheduledTime.isBefore(now);
          if (aPast && !bPast) return 1;  // a is past, b is future -> a comes after b
          if (!aPast && bPast) return -1; // a is future, b is past -> a comes before b
          if (!aPast && !bPast) {
            // both are future -> sort ascending (closest to now first)
            return a.scheduledTime.compareTo(b.scheduledTime);
          } else {
            // both are past -> sort descending (newest past first)
            return b.scheduledTime.compareTo(a.scheduledTime);
          }
        });
    } catch (_) {
      return [];
    }
  }

  static Future<List<ScheduleModel>> getUpcoming() async {
    try {
      final all = await getAll();
      final now = DateTime.now();
      return all.where((s) => s.scheduledTime.isAfter(now)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> delete(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await getAll();
      list.removeWhere((e) => e.id == id);
      await prefs.setString(_key, jsonEncode(list.map((e) => e.toMap()).toList()));
    } catch (_) {}
  }

  static Future<void> deleteAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }}
