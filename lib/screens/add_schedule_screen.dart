import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../models/schedule_model.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';

class AddScheduleScreen extends StatefulWidget {
  const AddScheduleScreen({super.key});

  @override
  State<AddScheduleScreen> createState() => _AddScheduleScreenState();
}

class _AddScheduleScreenState extends State<AddScheduleScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(hours: 1));
  bool _saving = false;
  int _preAlarmMinutes = 5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final defaultMins = await SettingsService.getPreAlarmMinutes();
    setState(() {
      _preAlarmMinutes = defaultMins;
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF6C63FF)),
        ),
        child: child!,
      ),
    );
    if (d != null) {
      setState(() => _selectedDate = DateTime(
            d.year, d.month, d.day,
            _selectedDate.hour, _selectedDate.minute,
          ));
    }
  }

  Future<void> _pickTime() async {
    DateTime tempTime = _selectedDate;
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        color: const Color(0xFF1C1C22),
        child: Column(
          children: [
            Container(
              color: const Color(0xFF0F0F13),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Text('Pilih Jam', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, decoration: TextDecoration.none)),
                  ),
                  CupertinoButton(
                    child: const Text('Selesai', style: TextStyle(color: Color(0xFF00E5FF))),
                    onPressed: () => Navigator.of(ctx).pop(),
                  )
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  brightness: Brightness.dark,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(color: Colors.white, fontSize: 22),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: _selectedDate,
                  use24hFormat: true,
                  onDateTimeChanged: (DateTime newTime) {
                    tempTime = newTime;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
    setState(() => _selectedDate = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day,
          tempTime.hour, tempTime.minute,
        ));
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Judul tidak boleh kosong')),
      );
      return;
    }
    if (_selectedDate.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waktu sudah lewat, pilih waktu lain')),
      );
      return;
    }

    final existing = await DatabaseService.getUpcoming();
    for (final s in existing) {
      if (s.scheduledTime.year == _selectedDate.year &&
          s.scheduledTime.month == _selectedDate.month &&
          s.scheduledTime.day == _selectedDate.day &&
          s.scheduledTime.hour == _selectedDate.hour &&
          s.scheduledTime.minute == _selectedDate.minute) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1C1C22),
              title: const Text('Waktu Bentrok', style: TextStyle(color: Colors.white)),
              content: Text('Jam segini udah ada jadwal "${s.title}". Silakan pilih menit atau jam lain ya!',
                  style: const TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup', style: TextStyle(color: Color(0xFF00E5FF))),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    setState(() => _saving = true);
    final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final preNotifId = _preAlarmMinutes > 0 ? notifId + 100000 : null;
    
    final model = ScheduleModel(
      id: notifId,
      title: _titleController.text.trim(),
      scheduledTime: _selectedDate,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      notificationId: notifId,
      preAlarmMinutes: _preAlarmMinutes,
      preNotificationId: preNotifId,
    );
    await DatabaseService.insert(model);
    await NotificationService.scheduleNotification(
      id: notifId,
      preId: preNotifId,
      title: '⏰ ${model.title}',
      body: model.note ?? model.title,
      scheduledTime: model.scheduledTime,
      preAlarmMinutes: model.preAlarmMinutes,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Jadwal "${model.title}" berhasil dibuat!'),
          backgroundColor: const Color(0xFF1B4332),
        ),
      );
      Navigator.pop(context, model);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F13),
        title: const Text('Tambah Jadwal', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Judul *'),
            _textField(_titleController, 'Contoh: Meeting, Dokter, Gym...'),
            const SizedBox(height: 20),
            _label('Catatan (opsional)'),
            _textField(_noteController, 'Tambahan info...', maxLines: 2),
            const SizedBox(height: 24),
            _label('Tanggal & Waktu'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _dateTimeCard(
                    icon: Icons.calendar_today_rounded,
                    label: DateFormat('EEE, d MMM yyyy').format(_selectedDate),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateTimeCard(
                    icon: Icons.access_time_rounded,
                    label: DateFormat('HH:mm').format(_selectedDate),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _label('Pengingat (Pre-Alarm)'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _preAlarmMinutes,
                  dropdownColor: const Color(0xFF1C1C22),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Tepat Waktu (0 menit)')),
                    DropdownMenuItem(value: 5, child: Text('5 Menit Sebelumnya')),
                    DropdownMenuItem(value: 15, child: Text('15 Menit Sebelumnya')),
                    DropdownMenuItem(value: 30, child: Text('30 Menit Sebelumnya')),
                    DropdownMenuItem(value: 60, child: Text('1 Jam Sebelumnya')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _preAlarmMinutes = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF00E5FF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Simpan Reminder',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      );

  Widget _textField(TextEditingController ctrl, String hint, {int maxLines = 1}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          filled: true,
          fillColor: const Color(0xFF1C1C22),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF00E5FF)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      );

  Widget _dateTimeCard({required IconData icon, required String label, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF00E5FF), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      );
}
