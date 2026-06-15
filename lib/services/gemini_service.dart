import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static GenerativeModel? _model;
  static ChatSession? _chat;

  static void init() {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) {
       print('WARNING: GEMINI_API_KEY is not set via --dart-define!');
    }

    _model = GenerativeModel(
      model: 'gemini-3.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
      systemInstruction: Content.system('''
Kamu adalah AI asisten jadwal pribadi yang super pintar (setara GPT), asik, proaktif, dan humoris.

ATURAN PENTING:
1. GAYA BAHASA: Ikutin gaya bahasa user. Kalau user pakai "gue/lo", balas dengan santai. Pakai emoji. Jangan kaku. Jika user bertanya hal di luar jadwal, tanggapi dengan ramah tapi tetap fokus ke tugas asisten.
2. BACA KONTEKS: Jika ada [SYSTEM_CONTEXT], itu adalah daftar jadwal saat ini (ID, Judul, Waktu). Ini adalah data yang 100% akurat.
3. MEMORI & MULTI-TURN: Kamu mengingat percakapan sebelumnya. Jika user bilang "hapus yang itu" atau "ganti jamnya jadi jam 3", ingat jadwal apa yang sedang dibahas sebelumnya.
4. ANALISIS MAKSUD USER: 
   - User mungkin meminta 1 atau lebih aksi sekaligus (misal "hapus jadwal x lalu buat jadwal y").
   - Pahami kalimat implisit dan singkatan. 
   - Jika "hapus", hasilkan action "delete" dengan ID terkait.
   - Jika "buat", hasilkan action "create" dengan title dan datetime.
   - Jika "ganti/ubah", hasilkan action "update" dengan ID terkait beserta title/datetime baru.
   - Jika jadwal bentrok, beri tahu user di text balasanmu tapi tetap jalankan jika user memaksa.
5. OUTPUT JSON: Kamu WAJIB mengembalikan JSON murni dengan skema berikut:
{
  "response_text": "Balasan asikmu ke user",
  "actions": [
    {
      "type": "create|update|delete",
      "id": 12345, // wajib untuk update/delete (ambil dari SYSTEM_CONTEXT)
      "title": "Judul acara", // wajib create, opsional update
      "datetime": "YYYY-MM-DDTHH:mm:ss" // wajib create, opsional update
    }
  ]
}
Jika hanya ngobrol biasa, array "actions" biarkan kosong [].
5. REFERENSI WAKTU: Waktu sekarang ada di [WAKTU_SEKARANG:...].
'''),
    );
    _chat = _model!.startChat();
  }

  static Future<GeminiResponse> sendMessage(String message, {String? contextData}) async {
    if (_model == null) init();

    try {
      final nowStr = DateTime.now().toIso8601String();
      final timeContext = '[WAKTU_SEKARANG: $nowStr]';
      
      final fullMessage = contextData != null && contextData.isNotEmpty 
          ? '$timeContext\n[SYSTEM_CONTEXT:\n$contextData]\nUser Chat: $message' 
          : '$timeContext\nUser Chat: $message';
          
      final response = await _chat!.sendMessage(Content.text(fullMessage));
      final text = response.text ?? '{}';
      return _parseResponse(text);
    } on GenerativeAIException catch (e) {
      return GeminiResponse(
        displayText: 'Waduh ada error dari AI: ${e.message}',
        actions: [],
        isError: true,
      );
    } catch (e) {
      return GeminiResponse(
        displayText: 'Koneksi bermasalah. Coba lagi ya.',
        actions: [],
        isError: true,
      );
    }
  }

  static GeminiResponse _parseResponse(String raw) {
    try {
      final map = jsonDecode(raw);
      final displayText = map['response_text'] as String? ?? 'Oke!';
      final List<dynamic> actionsList = map['actions'] ?? [];
      
      List<ParsedAction> actions = [];
      for (var a in actionsList) {
        if (a is Map<String, dynamic>) {
          final type = a['type'] as String?;
          if (type != null) {
            actions.add(ParsedAction(
              type: type,
              title: a['title'] as String?,
              datetime: a['datetime'] != null ? DateTime.tryParse(a['datetime'].toString()) : null,
              id: a['id'] is int ? a['id'] as int : (a['id'] != null ? int.tryParse(a['id'].toString()) : null),
            ));
          }
        }
      }
      return GeminiResponse(displayText: displayText, actions: actions);
    } catch (e) {
      return GeminiResponse(displayText: 'Error parse AI response: $e', actions: []);
    }
  }

  static void resetChat() {
    _chat = _model?.startChat();
  }
}

class GeminiResponse {
  final String displayText;
  final List<ParsedAction> actions;
  final bool isError;
  GeminiResponse({required this.displayText, required this.actions, this.isError = false});
}

class ParsedAction {
  final String type; // 'create', 'delete', 'update'
  final String? title;
  final DateTime? datetime;
  final int? id;
  ParsedAction({required this.type, this.title, this.datetime, this.id});
}
