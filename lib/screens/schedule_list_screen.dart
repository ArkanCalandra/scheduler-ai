import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/schedule_model.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class ScheduleListScreen extends StatefulWidget {
  const ScheduleListScreen({super.key});

  @override
  State<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends State<ScheduleListScreen> {
  List<ScheduleModel> _upcoming = [];
  List<ScheduleModel> _past = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DatabaseService.getAll();
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _upcoming = data.where((s) => s.scheduledTime.isAfter(now)).toList();
        _past = data.where((s) => !s.scheduledTime.isAfter(now)).toList();
        // Sort upcoming: nearest first
        _upcoming.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
        // Sort past: most recent first
        _past.sort((a, b) => b.scheduledTime.compareTo(a.scheduledTime));
      });
    }
  }

  Future<void> _delete(ScheduleModel s) async {
    await NotificationService.cancel(s.notificationId);
    await DatabaseService.delete(s.id);
    await _load();
  }

  Future<void> _deleteAll() async {
    await NotificationService.cancelAll();
    await DatabaseService.deleteAll();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F13),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F0F13),
          title: const Text(
            'Daftar Jadwal',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            indicatorColor: Color(0xFF00E5FF),
            labelColor: Color(0xFF00E5FF),
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(text: 'Mendatang'),
              Tab(text: 'Terlewat'),
            ],
          ),
          actions: [
            if (_upcoming.isNotEmpty || _past.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                tooltip: 'Hapus semua',
                onPressed: _confirmDeleteAll,
              ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildList(_upcoming, isPastTab: false),
            _buildList(_past, isPastTab: true),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<ScheduleModel> list, {required bool isPastTab}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(isPastTab ? 'Belum ada jadwal yang terlewat' : 'Belum ada reminder mendatang',
                style: const TextStyle(color: Colors.white38, fontSize: 16)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildCard(list[i], isPast: isPastTab),
    );
  }

  Widget _buildCard(ScheduleModel s, {required bool isPast}) {
    final now = DateTime.now();
    final diff = s.scheduledTime.difference(now);
    
    final accentColor = isPast ? Colors.grey : const Color(0xFF00E5FF);
    final borderColor = isPast ? Colors.white12 : Colors.white.withOpacity(0.05);
    final titleStyle = TextStyle(
      color: isPast ? Colors.white38 : Colors.white,
      fontWeight: FontWeight.w600,
      decoration: isPast ? TextDecoration.lineThrough : null,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isPast ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
            color: accentColor,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(s.title, style: titleStyle),
            ),
            if (isPast)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Selesai',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEE, d MMM yyyy • HH:mm').format(s.scheduledTime),
              style: TextStyle(
                color: isPast ? Colors.white24 : Colors.white54,
                fontSize: 13,
              ),
            ),
            Text(
              _formatDiff(diff, isPast),
              style: TextStyle(color: accentColor, fontSize: 12),
            ),
            if (s.note != null)
              Text(
                s.note!,
                style: TextStyle(
                  color: isPast ? Colors.white12 : Colors.white38,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: () => _confirmDelete(s),
        ),
      ),
    );
  }

  String _formatDiff(Duration d, bool isPast) {
    if (isPast) {
      return 'Sudah lewat';
    }
    if (d.inDays > 0) return 'dalam ${d.inDays} hari';
    if (d.inHours > 0) return 'dalam ${d.inHours} jam';
    if (d.inMinutes > 0) return 'dalam ${d.inMinutes} menit';
    return 'sebentar lagi';
  }

  void _confirmDelete(ScheduleModel s) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C22),
          title: const Text('Hapus reminder?', style: TextStyle(color: Colors.white)),
          content: Text('"${s.title}"', style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Batal', style: TextStyle(color: Colors.white54))),
            TextButton(
                onPressed: () { Navigator.pop(context); _delete(s); },
                child: const Text('Hapus', style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      );

  void _confirmDeleteAll() => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C22),
          title: const Text('Hapus semua?', style: TextStyle(color: Colors.white)),
          content: const Text('Semua reminder akan dihapus.',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Batal', style: TextStyle(color: Colors.white54))),
            TextButton(
                onPressed: () { Navigator.pop(context); _deleteAll(); },
                child: const Text('Hapus Semua', style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      );
}
