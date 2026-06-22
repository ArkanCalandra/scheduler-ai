import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  String _aiTone = 'casual';
  int _preAlarmMinutes = 5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final name = await SettingsService.getUserName();
    final tone = await SettingsService.getAiTone();
    final preAlarm = await SettingsService.getPreAlarmMinutes();
    setState(() {
      _nameController.text = name;
      _aiTone = tone;
      _preAlarmMinutes = preAlarm;
    });
  }

  Future<void> _saveSettings() async {
    await SettingsService.setUserName(_nameController.text.trim());
    await SettingsService.setAiTone(_aiTone);
    await SettingsService.setPreAlarmMinutes(_preAlarmMinutes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengaturan berhasil disimpan!')),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteAllSchedules() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C22),
        title: const Text('Hapus Semua Jadwal?', style: TextStyle(color: Colors.white)),
        content: const Text('Semua jadwal dan alarm yang aktif akan dihapus permanen. Lanjutkan?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.deleteAll();
      await NotificationService.cancelAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semua jadwal telah dihapus')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F13),
        title: const Text('Pengaturan', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Personalisasi'),
            _label('Nama Panggilan (Opsional)'),
            _textField(_nameController, 'Biar AI kenal sama lo (misal: Bro)'),
            const SizedBox(height: 20),
            
            _label('Gaya Bahasa AI'),
            _dropdown<String>(
              value: _aiTone,
              items: const [
                DropdownMenuItem(value: 'casual', child: Text('Santai / Gaul')),
                DropdownMenuItem(value: 'formal', child: Text('Formal / Sopan')),
                DropdownMenuItem(value: 'robot', child: Text('Singkat / Robot')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _aiTone = val);
              },
            ),
            const SizedBox(height: 30),

            _sectionTitle('Alarm & Notifikasi'),
            _label('Default Waktu Pre-Alarm'),
            _dropdown<int>(
              value: _preAlarmMinutes,
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
            const SizedBox(height: 40),

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
                  onPressed: _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Simpan Pengaturan',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
              ),
            ),
            const SizedBox(height: 40),
            
            _sectionTitle('Zona Berbahaya', color: Colors.redAccent),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _deleteAllSchedules,
                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                label: const Text('Hapus Semua Jadwal', style: TextStyle(color: Colors.redAccent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, {Color color = const Color(0xFF00E5FF)}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(text, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      );

  Widget _textField(TextEditingController ctrl, String hint) =>
      TextField(
        controller: ctrl,
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

  Widget _dropdown<T>({required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: const Color(0xFF1C1C22),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
