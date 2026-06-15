import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import '../models/schedule_model.dart';
import '../services/gemini_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/connectivity_service.dart';
import '../services/ai_parser.dart';
import '../services/settings_service.dart';
import 'schedule_list_screen.dart';
import 'add_schedule_screen.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;


  @override
  void initState() {
    super.initState();
    _addBotMessage('Halo! Gw asisten jadwal lo 🤖\nMau set reminder apa hari ini?');
  }

  void _addBotMessage(String text, {MessageType type = MessageType.text}) {
    setState(() {
      _messages.add(ChatMessage(text: text, sender: MessageSender.bot, type: type));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: text, sender: MessageSender.user));
      _isTyping = true;
    });
    _scrollToBottom();

    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;
    
    final isOnline = await ConnectivityService.isOnline();
    if (isOnline) {
      final upcomingSchedules = await DatabaseService.getUpcoming();
      String contextStr = upcomingSchedules.isEmpty 
          ? 'Kosong' 
          : upcomingSchedules.map((s) => 'ID:${s.id} | Judul:${s.title} | Waktu:${s.scheduledTime.toIso8601String()}').join('\n');
          
      final geminiRes = await GeminiService.sendMessage(text, contextData: contextStr);
      
      if (!mounted) return;
      setState(() => _isTyping = false);

      if (!geminiRes.isError) {
        if (geminiRes.actions.isNotEmpty) {
          bool hasCreate = false;
          for (final action in geminiRes.actions) {
            if (action.type == 'create' && action.title != null && action.datetime != null) {
              final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000 + action.title.hashCode;
              final preMins = await SettingsService.getPreAlarmMinutes();
              final preNotifId = preMins > 0 ? notifId + 100000 : null;

              final model = ScheduleModel(
                id: notifId,
                title: action.title!,
                scheduledTime: action.datetime!,
                notificationId: notifId,
                preAlarmMinutes: preMins,
                preNotificationId: preNotifId,
              );
              await DatabaseService.insert(model);
              await NotificationService.scheduleNotification(
                id: notifId,
                preId: preNotifId,
                title: '⏰ ${action.title}',
                body: 'Waktunya: ${DateFormat('HH:mm').format(action.datetime!)}',
                scheduledTime: action.datetime!,
                preAlarmMinutes: preMins,
              );
              hasCreate = true;
            } else if (action.type == 'delete' && action.id != null) {
              ScheduleModel? target;
              try { target = upcomingSchedules.firstWhere((s) => s.id == action.id); } catch (_) {}
              
              if (target != null) {
                await DatabaseService.delete(target.id);
                await NotificationService.cancel(target.notificationId);
              }
            } else if (action.type == 'update' && action.id != null) {
              ScheduleModel? target;
              try { target = upcomingSchedules.firstWhere((s) => s.id == action.id); } catch (_) {}
              
              if (target != null) {
                final newTitle = action.title ?? target.title;
                final newTime = action.datetime ?? target.scheduledTime;
                
                await DatabaseService.delete(target.id);
                await NotificationService.cancel(target.notificationId);

                final updatedModel = ScheduleModel(
                  id: target.id,
                  title: newTitle,
                  scheduledTime: newTime,
                  note: target.note,
                  notificationId: target.notificationId,
                  preAlarmMinutes: target.preAlarmMinutes,
                  preNotificationId: target.preNotificationId,
                );
                await DatabaseService.insert(updatedModel);
                await NotificationService.scheduleNotification(
                  id: target.notificationId,
                  preId: target.preNotificationId,
                  title: '⏰ $newTitle',
                  body: target.note ?? newTitle,
                  scheduledTime: newTime,
                  preAlarmMinutes: target.preAlarmMinutes,
                );
              }
            }
          }
          _addBotMessage(geminiRes.displayText, type: hasCreate ? MessageType.scheduleCreated : MessageType.text);
        } else {
           _addBotMessage(geminiRes.displayText);
        }
        return;
      }

      debugPrint('Gemini Error: ${geminiRes.displayText}. Falling back to offline parser...');
    }

    setState(() => _isTyping = false);

    final isId = AiParser.isIndonesian(text);
    final lowerText = text.toLowerCase();
    
    // 1. Cek apakah user mau menghapus jadwal via chat
    final isDeleteIntent = RegExp(r'\b(hapus|delete|batal|cancel|remove|hilangkan|clear)\b').hasMatch(lowerText);
    if (isDeleteIntent) {
      final upcoming = await DatabaseService.getUpcoming();
      String targetKeyword = lowerText
          .replaceAll(RegExp(r'\b(hapus|delete|batal|cancel|remove|hilangkan|clear|jadwal|reminder|acara|event|saya|gw|gue|my|the)\b'), '')
          .trim();
      
      if (targetKeyword.isEmpty) {
        _addBotMessage(isId 
            ? 'Mau hapus jadwal yang mana bro? Coba ketik "hapus [nama jadwal]" ya.' 
            : 'Which schedule do you want to delete? Try typing "delete [schedule name]".');
        return;
      }
      
      ScheduleModel? match;
      for (final s in upcoming) {
        if (s.title.toLowerCase().contains(targetKeyword)) {
          match = s;
          break;
        }
      }
      
      if (match != null) {
        await DatabaseService.delete(match.id);
        await NotificationService.cancel(match.notificationId);
        _addBotMessage(isId 
            ? 'Siap! Jadwal "${match.title}" buat tanggal ${DateFormat('d MMM yyyy, HH:mm').format(match.scheduledTime)} udah berhasil gw hapus ya! 🗑️'
            : 'Got it! Schedule "${match.title}" for ${DateFormat('d MMM yyyy, HH:mm').format(match.scheduledTime)} has been successfully deleted! 🗑️');
      } else {
        _addBotMessage(isId
            ? 'Aduh, gw cari-cari jadwal dengan kata kunci "$targetKeyword" ga ketemu nih. Coba cek ejaan atau ketik "lihat jadwal" buat pastiin.'
            : 'Sorry, I couldn\'t find any schedule matching "$targetKeyword". Try typing "list schedule" to check.');
      }
      return;
    }

    // 2. Cek apakah user mau mengganti/reschedule jadwal via chat
    final isRescheduleIntent = RegExp(r'\b(ganti|pindah|ubah|reschedule|change|move)\b').hasMatch(lowerText);
    if (isRescheduleIntent) {
      final allSchedules = await DatabaseService.getAll();
      final newScheduleData = AiParser.extractSchedule(text);
      if (newScheduleData == null) {
        _addBotMessage(isId 
            ? 'Jam atau tanggal barunya kurang jelas nih. Coba ketik "ganti jadwal [nama] jadi [waktu]"'
            : 'I couldn\'t understand the new time. Try: "change [name] to [time]".');
        return;
      }
      
      String cleanedForTitle = lowerText
          .replaceAll(RegExp(r'\b(ganti|pindah|ubah|reschedule|change|move|jadwal|reminder|acara|event|saya|gw|gue|my|the)\b'), '')
          .replaceAll(RegExp(r'\b(jadi|ke|to|into|at|@|jam|pukul)\b'), '')
          .trim();
          
      final extractedNewTitle = newScheduleData.title.toLowerCase();
      cleanedForTitle = cleanedForTitle.replaceAll(extractedNewTitle, '').trim();
      cleanedForTitle = cleanedForTitle.replaceAll(RegExp(r'\b\d{1,2}(?:[:.]\d{2})?\b'), '').trim();
      cleanedForTitle = cleanedForTitle.replaceAll(RegExp(r'\b(?:am|pm|pagi|siang|sore|malam|malem|besok|lusa|hari ini)\b'), '').trim();
      cleanedForTitle = cleanedForTitle.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

      if (cleanedForTitle.isEmpty) {
        cleanedForTitle = extractedNewTitle;
      }

      ScheduleModel? match;
      for (final s in allSchedules) {
        if (s.title.toLowerCase().contains(cleanedForTitle) || cleanedForTitle.contains(s.title.toLowerCase())) {
          match = s;
          break;
        }
      }

      if (match != null) {
        bool isConflict = false;
        String conflictTitle = '';
        for (final s in allSchedules) {
          if (s.id == match.id) continue;
          final diff = s.scheduledTime.difference(newScheduleData.scheduledTime).inMinutes.abs();
          if (diff < 1) {
            isConflict = true;
            conflictTitle = s.title;
            break;
          }
        }

        if (isConflict) {
          _addBotMessage(isId
              ? 'Gagal mindahin jadwal, bro! Soalnya jam segitu bentrok sama jadwal "$conflictTitle". Hapus dulu jadwal "$conflictTitle" atau pilih jam lain ya!'
              : 'Rescheduling failed! That time conflicts with "$conflictTitle". Please delete "$conflictTitle" or choose another time!');
          return;
        }

        final oldNote = match.note;
        await DatabaseService.delete(match.id);
        await NotificationService.cancel(match.notificationId);

        final updatedModel = ScheduleModel(
          id: match.id,
          title: match.title,
          scheduledTime: newScheduleData.scheduledTime,
          note: oldNote,
          notificationId: match.notificationId,
          preAlarmMinutes: match.preAlarmMinutes,
          preNotificationId: match.preNotificationId,
        );
        await DatabaseService.insert(updatedModel);
        await NotificationService.scheduleNotification(
          id: match.notificationId,
          preId: match.preNotificationId,
          title: '⏰ ${match.title}',
          body: oldNote ?? match.title,
          scheduledTime: newScheduleData.scheduledTime,
          preAlarmMinutes: match.preAlarmMinutes,
        );

        _addBotMessage(isId
            ? 'Sip! Jadwal "${match.title}" berhasil gw pindahin ke tanggal ${DateFormat('d MMM yyyy, HH:mm').format(newScheduleData.scheduledTime)} ya! 🗓️'
            : 'Got it! Schedule "${match.title}" has been successfully moved to ${DateFormat('d MMM yyyy, HH:mm').format(newScheduleData.scheduledTime)}! 🗓️');
      } else {
        _addBotMessage(isId
            ? 'Gw ga nemu jadwal bernama "$cleanedForTitle" buat dipindahin. Coba cek ejaan atau ketik "lihat jadwal".'
            : 'I couldn\'t find any schedule named "$cleanedForTitle" to reschedule. Try typing "list schedule" to check.');
      }
      return;
    }

    // 3. Ekstrak jadwal baru
    final schedule = AiParser.extractSchedule(text);

    if (schedule != null) {
      final upcoming = await DatabaseService.getUpcoming();
      bool isConflict = false;
      String conflictTitle = '';
      for (final s in upcoming) {
        final diff = s.scheduledTime.difference(schedule.scheduledTime).inMinutes.abs();
        if (diff < 1) {
          isConflict = true;
          conflictTitle = s.title;
          break;
        }
      }

      if (isConflict) {
        _addBotMessage(isId
            ? 'Waduh, ga bisa dibikinin bro! Soalnya jam segitu bentrok sama jadwal "$conflictTitle". Hapus dulu jadwal "$conflictTitle" kalau mau ganti, atau ketik "ganti jadwal $conflictTitle jadi [jam baru]" buat mindahin.'
            : 'Hold on, I can\'t schedule that! It conflicts with "$conflictTitle". Delete "$conflictTitle" first to replace it, or type "change $conflictTitle to [new time]".');
        return;
      }

      final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final preMins = schedule.preAlarmMinutes ?? await SettingsService.getPreAlarmMinutes();
      final preNotifId = preMins > 0 ? notifId + 100000 : null;

      final model = ScheduleModel(
        id: notifId,
        title: schedule.title,
        scheduledTime: schedule.scheduledTime,
        notificationId: notifId,
        preAlarmMinutes: preMins,
        preNotificationId: preNotifId,
      );
      await DatabaseService.insert(model);
      await NotificationService.scheduleNotification(
        id: notifId,
        preId: preNotifId,
        title: '⏰ ${schedule.title}',
        body: 'Waktunya: ${DateFormat('HH:mm').format(schedule.scheduledTime)}',
        scheduledTime: schedule.scheduledTime,
        preAlarmMinutes: preMins,
      );
      
      final uName = await SettingsService.getUserName();
      final uTone = await SettingsService.getAiTone();
      String response = AiParser.generateResponse(
        userText: text, isId: isId, schedule: schedule, userName: uName, aiTone: uTone
      );
      _addBotMessage(response, type: MessageType.scheduleCreated);
    } else {
      final uName = await SettingsService.getUserName();
      final uTone = await SettingsService.getAiTone();
      final response = AiParser.generateResponse(
        userText: text, isId: isId, schedule: null, userName: uName, aiTone: uTone
      );
      if (response == '__SHOW_SCHEDULES__') {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ScheduleListScreen()),
          );
        }
        _addBotMessage(isId ? 'Membuka jadwal...' : 'Opening schedules...');
      } else {
        _addBotMessage(response);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (_, i) {
                if (_isTyping && i == _messages.length) return _buildTypingIndicator();
                return _buildBubble(_messages[i]);
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF16213E),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: Image.asset('logo.png', width: 20, height: 20, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('VEXRA',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              StreamBuilder<bool>(
                stream: ConnectivityService.onlineStream,
                builder: (context, snapshot) {
                  final isOnline = snapshot.data ?? false;
                  return Text(
                    isOnline ? 'Online AI by VEXRA Tech' : 'Offline AI by VEXRA Tech',
                    style: TextStyle(
                      color: isOnline ? Colors.greenAccent : Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white70),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
          tooltip: 'Pengaturan',
        ),
        IconButton(
          icon: const Icon(Icons.calendar_month, color: Colors.white70),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ScheduleListScreen()),
          ),
          tooltip: 'Jadwal',
        ),
      ],
    );
  }



  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.sender == MessageSender.user;
    Color bubbleColor;
    if (isUser) {
      bubbleColor = const Color(0xFF6C63FF);
    } else if (msg.type == MessageType.scheduleCreated) {
      bubbleColor = const Color(0xFF1B4332);
    } else if (msg.type == MessageType.error) {
      bubbleColor = const Color(0xFF3B1A1A);
    } else {
      bubbleColor = const Color(0xFF16213E);
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: msg.type == MessageType.scheduleCreated
              ? Border.all(color: Colors.greenAccent.withOpacity(0.3))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.type == MessageType.scheduleCreated)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle, color: Colors.greenAccent, size: 14),
                    SizedBox(width: 4),
                    Text('Reminder dibuat!',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                DateFormat('HH:mm').format(msg.time),
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => _dot(i)),
        ),
      ),
    );
  }

  Widget _dot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + index * 200),
      builder: (_, v, __) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.3 + v * 0.5),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: const Color(0xFF16213E),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          // Tombol tambah manual
          GestureDetector(
            onTap: () async {
              final result = await Navigator.push<ScheduleModel>(
                context,
                MaterialPageRoute(builder: (_) => const AddScheduleScreen()),
              );
              // manual addition shows its own snackbar now, no need to add bot message
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F3460),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add, color: Colors.white70, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ketik jadwal lo...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFF0F3460),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _handleSend(),
              textInputAction: TextInputAction.send,
              enabled: true,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _handleSend,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF6C63FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
