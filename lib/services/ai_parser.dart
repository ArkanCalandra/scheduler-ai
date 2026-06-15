/// Offline AI parser — detects language, extracts schedule info,
/// and generates a natural response that mirrors the user's language/tone.
class AiParser {
  // ─── Language Detection ───────────────────────────────────────────────────

  static bool isIndonesian(String text) {
    const idWords = [
      'gw', 'gue', 'aku', 'saya', 'lo', 'lu', 'kamu', 'ada', 'mau', 'mw',
      'jam', 'tanggal', 'besok', 'lusa', 'minggu', 'bulan', 'tahun',
      'rapat', 'ketemu', 'janjian', 'acara', 'hari', 'ini',
      'ya', 'iya', 'oke', 'ok', 'deh', 'dong', 'sih', 'nih', 'lah',
      'tolong', 'ingetin', 'jadwal', 'semua', 'lihat', 'hapus', 'batal',
      'malem', 'malam', 'pagi', 'siang', 'sore', 'nanti', 'tadi', 'ke', 'pasar'
    ];
    final lower = text.toLowerCase();
    return idWords.any((w) => lower.contains(w));
  }

  // ─── Schedule Extraction ──────────────────────────────────────────────────

  static ParsedSchedule? extractSchedule(String text) {
    final lower = text.toLowerCase();
    final now = DateTime.now();

    final relTime = _extractRelativeTime(lower, now);
    String? title = _extractTitle(text);

    if (relTime != null) {
      return ParsedSchedule(
        title: title ?? _fallbackTitle(text),
        scheduledTime: relTime,
      );
    }

    DateTime? date = _extractDate(lower, now);
    TimeOfDay? tod = _extractTime(lower);

    // Jika tidak ada jam spesifik, default ke waktu saat ini (ditambah 1 menit agar selalu di masa depan)
    if (tod == null) {
      final defaultTime = now.add(const Duration(minutes: 1));
      tod = TimeOfDay(
        hour: defaultTime.hour,
        minute: defaultTime.minute,
        hasExplicitSuffix: false,
        dateWasExplicit: false,
      );
    }

    date ??= DateTime(now.year, now.month, now.day);

    int hour = tod.hour;
    int minute = tod.minute;

    // smart AM/PM: kalau ga ada suffix, tebak berdasarkan jam sekarang
    if (!tod.hasExplicitSuffix) {
      hour = _smartHour(hour, now);
    }

    var scheduled = DateTime(date.year, date.month, date.day, hour, minute);

    // kalau hasilnya masih di masa lalu
    if (scheduled.isBefore(now)) {
      // kalau user nyebut tanggal/hari eksplisit → emang udah lewat
      if (tod.dateWasExplicit) return null;
      // kalau cuma jam → geser ke besok
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final preAlarmMins = _extractPreAlarmMinutes(lower, scheduled);

    return ParsedSchedule(
      title: title ?? _fallbackTitle(text),
      scheduledTime: scheduled,
      preAlarmMinutes: preAlarmMins,
    );
  }

  static int? _extractPreAlarmMinutes(String lowerText, DateTime scheduledTime) {
    // 1. "X menit/jam sebelumnya"
    final reBefore = RegExp(r'(\d+|setengah)\s*(jam|menit|hours|minutes)\s*(sebelumnya|sebelum|before)');
    final matchBefore = reBefore.firstMatch(lowerText);
    if (matchBefore != null) {
      final valStr = matchBefore.group(1)!;
      final unit = matchBefore.group(2)!;
      
      double value = 0;
      if (valStr == 'setengah') value = 0.5;
      else value = double.parse(valStr);

      if (unit.startsWith('jam') || unit.startsWith('hour')) {
        return (value * 60).toInt();
      }
      return value.toInt();
    }

    // 2. "ingetin dari jam XX" / "dari jam XX"
    final reFrom = RegExp(r'(?:ingetin|remind|dari|from)\s*(?:jam|pukul|at|@)?\s*(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|pagi|siang|sore|malam|malem)?\b');
    final matchesFrom = reFrom.allMatches(lowerText);
    
    for (final m in matchesFrom) {
      int h = int.parse(m.group(1)!);
      int min = m.group(2) != null ? int.parse(m.group(2)!) : 0;
      final suffix = m.group(3);
      if (suffix != null) h = _applySuffix(h, suffix);
      
      // smart hour
      if (suffix == null && h < 13) {
         if (scheduledTime.hour >= 12 && h < 12 && (h+12) < scheduledTime.hour) {
           h += 12; // convert to PM if reasonable
         }
      }

      var preTime = DateTime(scheduledTime.year, scheduledTime.month, scheduledTime.day, h, min);
      if (preTime.isBefore(scheduledTime)) {
        final diff = scheduledTime.difference(preTime).inMinutes;
        // if diff is reasonable for a pre-alarm (e.g. < 24 hours and > 0)
        if (diff > 0 && diff < 1440) return diff;
      }
    }
    return null;
  }

  static DateTime? _extractRelativeTime(String text, DateTime now) {
    // "X jam lagi", "X menit lagi", "setengah jam lagi"
    final re = RegExp(r'(\d+|setengah)\s*(jam|menit|hours|minutes)\s*(lagi|from now|later)');
    final match = re.firstMatch(text);
    if (match != null) {
      final valStr = match.group(1)!;
      final unit = match.group(2)!;
      
      double value = 0;
      if (valStr == 'setengah') {
        value = 0.5;
      } else {
        value = double.parse(valStr);
      }

      if (unit.startsWith('jam') || unit.startsWith('hour')) {
        return now.add(Duration(minutes: (value * 60).toInt()));
      } else {
        return now.add(Duration(minutes: value.toInt()));
      }
    }
    return null;
  }

  /// Smart hour: kalau user ketik "jam 8" tanpa keterangan,
  /// tebak AM atau PM berdasarkan jam sekarang.
  static int _smartHour(int hour, DateTime now) {
    if (hour >= 13) return hour; // 13-23 udah jelas malem
    if (hour == 0) return 0;

    final nowH = now.hour;

    // Coba dulu versi yang lebih dekat ke waktu sekarang
    // Kalau sekarang >= 12 (siang/sore/malem), prioritaskan PM
    if (nowH >= 12) {
      final pmHour = hour < 12 ? hour + 12 : hour;
      final amHour = hour;
      // pilih yang paling dekat ke depan dari sekarang
      final pmTime = pmHour > nowH ? pmHour : pmHour + 24;
      final amTime = amHour > nowH ? amHour : amHour + 24;
      return pmTime <= amTime ? pmHour : amHour;
    } else {
      // sekarang pagi → prioritaskan AM dulu
      final amHour = hour;
      final pmHour = hour + 12;
      final amTime = amHour > nowH ? amHour : amHour + 24;
      final pmTime = pmHour > nowH ? pmHour : pmHour + 24;
      return amTime <= pmTime ? amHour : pmHour;
    }
  }

  static DateTime? _extractDate(String text, DateTime now) {
    // hari ini
    if (text.contains('hari ini') || text.contains('today')) {
      return DateTime(now.year, now.month, now.day);
    }
    // besok / tomorrow
    if (text.contains('besok') || text.contains('tomorrow')) {
      final d = now.add(const Duration(days: 1));
      return DateTime(d.year, d.month, d.day);
    }
    // lusa / day after tomorrow
    if (text.contains('lusa') || text.contains('day after tomorrow')) {
      final d = now.add(const Duration(days: 2));
      return DateTime(d.year, d.month, d.day);
    }

    // tanggal DD / tgl DD
    final tanggalRe = RegExp(r'(?:tanggal|tgl|date)\s*(\d{1,2})(?:\s*(?:\/|-)\s*(\d{1,2}))?');
    final tMatch = tanggalRe.firstMatch(text);
    if (tMatch != null) {
      final day = int.parse(tMatch.group(1)!);
      final month = tMatch.group(2) != null ? int.parse(tMatch.group(2)!) : now.month;
      var year = now.year;
      var d = DateTime(year, month, day);
      if (d.isBefore(DateTime(now.year, now.month, now.day))) {
        d = DateTime(year + 1, month, day);
      }
      return d;
    }

    // DD/MM or DD-MM
    final slashRe = RegExp(r'\b(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?\b');
    final sMatch = slashRe.firstMatch(text);
    if (sMatch != null) {
      final day = int.parse(sMatch.group(1)!);
      final month = int.parse(sMatch.group(2)!);
      final year = sMatch.group(3) != null
          ? int.parse(sMatch.group(3)!)
          : now.year;
      return DateTime(year < 100 ? 2000 + year : year, month, day);
    }

    // named months
    final months = {
      'jan': 1, 'january': 1, 'januari': 1,
      'feb': 2, 'february': 2, 'februari': 2,
      'mar': 3, 'march': 3, 'maret': 3,
      'apr': 4, 'april': 4,
      'may': 5, 'mei': 5,
      'jun': 6, 'june': 6, 'juni': 6,
      'jul': 7, 'july': 7, 'juli': 7,
      'aug': 8, 'august': 8, 'agustus': 8,
      'sep': 9, 'september': 9,
      'oct': 10, 'october': 10, 'oktober': 10,
      'nov': 11, 'november': 11,
      'dec': 12, 'december': 12, 'desember': 12,
    };
    for (final entry in months.entries) {
      final re = RegExp(r'(\d{1,2})\s*' + entry.key);
      final m = re.firstMatch(text);
      if (m != null) {
        final day = int.parse(m.group(1)!);
        return DateTime(now.year, entry.value, day);
      }
    }

    return null;
  }

  static TimeOfDay? _extractTime(String text) {
    // jam/pukul HH:MM or HH.MM
    final colonRe = RegExp(r'(?:jam|pukul|at|@)\s*(\d{1,2})[:.](\d{2})\s*(am|pm|pagi|siang|sore|malam|malem)?');
    final cMatch = colonRe.firstMatch(text);
    if (cMatch != null) {
      int hour = int.parse(cMatch.group(1)!);
      final minute = int.parse(cMatch.group(2)!);
      final suffix = cMatch.group(3)?.toLowerCase();
      bool explicit = suffix != null;
      if (suffix != null) hour = _applySuffix(hour, suffix);
      return TimeOfDay(hour: hour, minute: minute, hasExplicitSuffix: explicit, dateWasExplicit: false);
    }

    // jam/pukul HH dengan suffix opsional
    final hourRe = RegExp(r'(?:jam|pukul|at|@)\s*(\d{1,2})\s*(am|pm|pagi|siang|sore|malam|malem)?');
    final hMatch = hourRe.firstMatch(text);
    if (hMatch != null) {
      int hour = int.parse(hMatch.group(1)!);
      final suffix = hMatch.group(2)?.toLowerCase();
      bool explicit = suffix != null;
      if (suffix != null) hour = _applySuffix(hour, suffix);
      return TimeOfDay(hour: hour, minute: 0, hasExplicitSuffix: explicit, dateWasExplicit: false);
    }

    // plain HH:MM or HH.MM
    final plainRe = RegExp(r'\b(\d{1,2})[:.](\d{2})\b');
    final pMatch = plainRe.firstMatch(text);
    if (pMatch != null) {
      return TimeOfDay(
        hour: int.parse(pMatch.group(1)!),
        minute: int.parse(pMatch.group(2)!),
        hasExplicitSuffix: false,
        dateWasExplicit: false,
      );
    }

    return null;
  }

  static int _applySuffix(int hour, String suffix) {
    if ((suffix == 'pm' || suffix == 'sore' || suffix == 'malam' || suffix == 'malem') && hour < 12) {
      return hour + 12;
    }
    if ((suffix == 'am' || suffix == 'pagi') && hour == 12) return 0;
    return hour;
  }

  static String? _extractTitle(String original) {
    var t = original
        .replaceAll(RegExp(r'(?:\d+|setengah)\s*(?:jam|menit|hours|minutes)\s*(?:lagi|from now|later)', caseSensitive: false), '')
        .replaceAll(RegExp(r'(?:tanggal|tgl|jam|pukul|at|@|date|remind me|ingetin|tolong|hari ini|today|besok|tomorrow|lusa)\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\d{1,2}[\/\-.:]\d{1,2}(?:[\/\-.:]\d{2,4})?'), '')
        .replaceAll(RegExp(r'\b\d{1,2}\b'), '')
        .replaceAll(RegExp(r'\b(?:am|pm|pagi|siang|sore|malam|malem)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'(?:ingetin|dari|sebelumnya|sebelum|before)\s*jam\s*\d{1,2}(?:[:.]\d{2})?', caseSensitive: false), '')
        .replaceAll(RegExp(r'\d+\s*(?:jam|menit|hours|minutes)\s*(?:sebelumnya|sebelum|before)', caseSensitive: false), '')
        .trim();

    // Clean scheduling action verbs/phrases from start
    t = t.replaceAll(RegExp(r'^(?:catat|mencatat|bikin|buat|jadwalin|ingetin|remind|tolong|plis|please|set|setup|tambah|tambahkan|add|create|new|schedule)\s+(?:buat|untuk|saya|gw|gue|me|to|for|a|an|the|jadwal|reminder|alarm)\s*', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'^(?:catat|mencatat|bikin|buat|jadwalin|ingetin|remind|tolong|plis|please|set|setup|tambah|tambahkan|add|create|new|schedule|nya)\s+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'^(?:catat|buat|untuk|to|for)\s+', caseSensitive: false), '');

    t = t.replaceAll(RegExp(r'^(?:gw|gue|aku|saya|i|ya|iya|oke|ok|ada|have|got|nanti|ntar)\s+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+(?:ya|dong|deh|sih|nih|lah|please|yaa|yaaa)$', caseSensitive: false), '');
    t = t.trim();

    return t.isNotEmpty ? _capitalize(t) : null;
  }

  static String _fallbackTitle(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('meeting') || lower.contains('rapat')) return 'Meeting';
    if (lower.contains('ketemu') || lower.contains('janjian')) return 'Janjian';
    if (lower.contains('dokter') || lower.contains('doctor') || lower.contains('dentist')) return 'Dokter';
    if (lower.contains('gym') || lower.contains('olahraga')) return 'Olahraga';
    if (lower.contains('makan') || lower.contains('lunch') || lower.contains('dinner')) return 'Makan';
    if (lower.contains('kuliah') || lower.contains('class') || lower.contains('sekolah')) return 'Kuliah';
    if (lower.contains('kerja') || lower.contains('work') || lower.contains('kantor')) return 'Kerja';
    return 'Reminder';
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ─── Response Generator ───────────────────────────────────────────────────

  static String generateResponse({
    required String userText,
    required bool isId,
    ParsedSchedule? schedule,
    String? errorReason,
    String userName = '',
    String aiTone = 'casual',
  }) {
    if (schedule != null) {
      return _confirmResponse(userText, isId, schedule, userName, aiTone);
    }
    if (errorReason == 'past') {
      return _pastResponse(isId, aiTone);
    }
    return _casualReply(userText, isId, userName, aiTone);
  }

  static String _pastResponse(bool isId, String aiTone) {
    if (aiTone == 'formal') {
      return isId 
        ? 'Mohon maaf, waktu tersebut telah berlalu. Silakan tentukan waktu di masa depan.'
        : 'I apologize, but that time has already passed. Please provide a future time.';
    }
    if (aiTone == 'robot') {
      return isId 
        ? '[ERROR: WAKTU_KADALUWARSA] Masukkan waktu di masa depan.'
        : '[ERROR: PAST_TIME] Please provide a future time.';
    }
    // casual default
    return isId
        ? _pickRandom([
            'Waduh, waktunya udah kelewat tuh bro 😅 Coba masukin jam atau tanggal yang belum lewat ya.',
            'Eh bentar, itu kan udah lewat lho. Mau gw set buat besok aja?',
            'Mesin waktu gw lagi rusak nih 🤣 Coba kasih waktu yang di masa depan ya!',
            'Kayaknya itu masa lalu deh. Kasih tau gw waktu yang baru dong!',
          ])
        : _pickRandom([
            'Whoops, that time has already passed 😅 Try a future date!',
            'Hold on, that\'s in the past. Give me a future time!',
            'My time machine is broken right now 🤣 Need a time in the future!',
            'That already passed! Want me to set it for tomorrow instead?',
          ]);
  }

  static String _confirmResponse(String userText, bool isId, ParsedSchedule s, String userName, String aiTone) {
    final timeStr = _formatTime(s.scheduledTime);
    final dateStr = _formatDate(s.scheduledTime, isId);
    final now = DateTime.now();
    final isToday = s.scheduledTime.day == now.day &&
        s.scheduledTime.month == now.month &&
        s.scheduledTime.year == now.year;
    final isTomorrow = s.scheduledTime.day == now.add(const Duration(days: 1)).day &&
        s.scheduledTime.month == now.add(const Duration(days: 1)).month;

    final nameGreeting = userName.isNotEmpty ? ' $userName' : '';

    String whenStr;
    if (isId) {
      whenStr = isToday ? 'hari ini jam $timeStr' : isTomorrow ? 'besok jam $timeStr' : '$dateStr jam $timeStr';
      if (aiTone == 'formal') {
        return 'Baik$nameGreeting. Pengingat untuk "${s.title}" telah dijadwalkan pada $whenStr.';
      } else if (aiTone == 'robot') {
        return '[JADWAL DITAMBAHKAN] "${s.title}" -> $whenStr';
      }
      // casual
      return _pickRandom([
        'Oke siap laksanakan$nameGreeting! Reminder "${s.title}" udah gw pasang buat $whenStr 🔔 Jangan sampe kelewat ya!',
        'Beres bos! Nanti gw ingetin masalah "${s.title}" $whenStr 👍 Aman!',
        'Sip$nameGreeting, udah gw catat nih. "${s.title}" — $whenStr ✅ Semangat!',
        'Noted! Gw bakal nge-ping lo soal "${s.title}" $whenStr 🔔 Serahkan ke gw!',
        'Mantap, alarm buat "${s.title}" nyala $whenStr ya. Jangan lupa! 🔥',
      ]);
    } else {
      whenStr = isToday ? 'today at $timeStr' : isTomorrow ? 'tomorrow at $timeStr' : '$dateStr at $timeStr';
      if (aiTone == 'formal') {
        return 'Noted$nameGreeting. The reminder for "${s.title}" has been scheduled for $whenStr.';
      } else if (aiTone == 'robot') {
        return '[SCHEDULE ADDED] "${s.title}" -> $whenStr';
      }
      // casual
      return _pickRandom([
        'Got it$nameGreeting! Reminder for "${s.title}" is locked in for $whenStr 🔔 I won\'t let you forget!',
        'Done and dusted! I\'ll remind you about "${s.title}" $whenStr 👍',
        'All set$nameGreeting! "${s.title}" — $whenStr ✅ Let\'s go!',
        'Noted! I\'ll be pinging you for "${s.title}" $whenStr 🔔 Leave it to me!',
      ]);
    }
  }

  static String _casualReply(String userText, bool isId, String userName, String aiTone) {
    final lower = userText.toLowerCase();
    final nameGreeting = userName.isNotEmpty ? ' $userName' : '';

    // Out of scope classifier (general questions or general topics)
    final outOfScopeKeywords = [
      'siapa', 'bagaimana', 'kenapa', 'mengapa', 'apa itu', 'jelaskan', 'cara membuat', 
      'coding', 'resep', 'tutorial', 'belajar', 'pemrograman', 'bahasa', 'presiden',
      'how to', 'why', 'who', 'what is', 'explain', 'recipe', 'code', 'programming', 
      'weather', 'cuaca', 'berita', 'news', 'hitung', 'math', 'matematika'
    ];
    if (outOfScopeKeywords.any((k) => lower.contains(k))) {
      return isId
          ? 'Maaf bro, gw asisten jadwal khusus offline. Gw ga bisa jawab pertanyaan umum atau tugas di luar urusan jadwal. Tapi kalau mau dibantuin pasang reminder, langsung ketik aja ya! ⏰😎'
          : 'Sorry, I am just a local offline scheduling assistant. I can\'t help with general questions or tasks. But if you want to set a reminder, just let me know! ⏰😎';
    }

    // greetings
    if (RegExp(r'\b(hi|hello|hey|halo|hai|hei)\b').hasMatch(lower)) {
      if (aiTone == 'formal') {
        return isId ? 'Halo$nameGreeting. Ada jadwal yang ingin Anda tambahkan?' : 'Hello$nameGreeting. Is there a schedule you want to add?';
      }
      if (aiTone == 'robot') {
        return isId ? '[SYSTEM_READY] Menunggu input jadwal.' : '[SYSTEM_READY] Waiting for schedule input.';
      }
      return isId
          ? _pickRandom([
              'Yoi, halo$nameGreeting! Gw Vexra AI, siap bantu ingetin jadwal lo hari ini! 😎',
              'Hai$nameGreeting! Gw Vexra AI. Gimana, ada jadwal padat yang mau gw bantu catet?',
              'Heyoo$nameGreeting! Vexra AI asisten lo siap beraksi nih. Ada acara apa?',
              'Halo bro! Sini gw (Vexra AI) bantuin ngurusin jadwal lo 🤖',
            ])
          : _pickRandom([
              'Hey$nameGreeting! I am Vexra AI. What would you like to schedule? 😊',
              'Hello$nameGreeting! Vexra AI here, need help with a reminder?',
              'Hi$nameGreeting! Vexra AI at your service. What should I remind you about?',
            ]);
    }

    // asking what it can do
    if (lower.contains('bisa apa') || lower.contains('what can you') ||
        lower.contains('help') || lower.contains('bantuin') || lower.contains('cara')) {
      return isId
          ? 'Gw Vexra AI, asisten pribadi lo yang asik! 😎 Lo tinggal chat aja kayak:\n• "Besok jam 3 nemuin klien, ingetin 1 jam sebelumnya"\n• "Tgl 20 jam 9 pagi ke dokter gigi"\nNtar gw aturin alarmnya otomatis! 📅'
          : 'I\'m Vexra AI, your cool personal assistant! 😎 Just chat naturally like:\n• "Tomorrow at 3pm client meeting, remind 1 hour before"\n• "Jan 20 at 9am dentist"\nI\'ll set the alarms automatically! 📅';
    }

    // list schedules
    if ((lower.contains('jadwal') && (lower.contains('list') || lower.contains('semua') || lower.contains('apa aja') || lower.contains('lihat'))) ||
        lower.contains('show schedule') || lower.contains('my reminder') || lower.contains('reminder gw')) {
      return '__SHOW_SCHEDULES__';
    }

    // thanks
    if (lower.contains('makasih') || lower.contains('thanks') || lower.contains('thank you') || lower.contains('thx')) {
      return isId
          ? _pickRandom(['Santai aja, itu emang kerjaan gw! 😎', 'Siap laksanakan! Kalau ada lagi kabarin aja yak.', 'Yoi, no problem bro! 👍', 'Sama-sama! Have a great day! ✨'])
          : _pickRandom(['You\'re totally welcome! 😎', 'Anytime! Let me know if you need more magic.', 'No problem! 👍']);
    }

    // ada kata jam tapi ga ke-parse → minta lebih spesifik
    if (lower.contains('jam') || lower.contains(' at ') || lower.contains('pukul')) {
      return isId
          ? _pickRandom([
              'Hmm, gw nangkep jamnya nih, tapi tanggalnya kapan ya? Tambahin "besok" atau spesifikin tgl-nya dong 😄',
              'Wah ini mau diset buat hari ini atau besok? Kasih tau detailnya dikit lagi ya bro 🙏',
            ])
          : _pickRandom([
              'Hmm, I didn\'t catch the date. Try adding "tomorrow" or a specific date 😄',
              'What date should I set this for? E.g. "tomorrow at 8pm meeting" 🙏',
            ]);
    }

    // default fallback — selalu ada response
    if (aiTone == 'formal') {
      return isId 
        ? 'Mohon maaf, saya belum memahami format tersebut. Coba sebutkan "besok jam 3 sore meeting".'
        : 'I apologize, I didn\'t catch that. Please use a format like "tomorrow at 3pm meeting".';
    }
    if (aiTone == 'robot') {
      return isId ? '[ERROR: INVALID_FORMAT] Gunakan format: [TANGGAL/HARI] jam [WAKTU] [ACARA]' : '[ERROR: INVALID_FORMAT] Use format: [DATE/DAY] at [TIME] [EVENT]';
    }
    return isId
          ? _pickRandom([
              'Aduh$nameGreeting, gw kurang nangkep nih maksudnya apa 😅 Mending bilang kayak "besok jam 3 sore meeting" ya!',
              'Eh$nameGreeting, bisa dibantu kasih tau waktu sama acaranya lebih detail? Biar gw gampang masukin jadwal 📅',
              'Hmm, gw belum nangkep poinnya. Coba ketik "tanggal 20 jam 9 dokter" gitu bro 🙏',
            ])
        : _pickRandom([
            'Hmm$nameGreeting, I didn\'t quite get that 😄 Try something like "tomorrow at 3pm meeting"!',
            'Could you be more specific? I need a time and event to set a reminder 📅',
            'Not sure what you mean. Try: "Jan 20 at 9am dentist" 🙏',
          ]);
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _formatDate(DateTime dt, bool isId) {
    final months = isId
        ? ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des']
        : ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _pickRandom(List<String> options) {
    options.shuffle();
    return options.first;
  }
}

class ParsedSchedule {
  final String title;
  final DateTime scheduledTime;
  final int? preAlarmMinutes;
  ParsedSchedule({required this.title, required this.scheduledTime, this.preAlarmMinutes});
}

class TimeOfDay {
  final int hour;
  final int minute;
  final bool hasExplicitSuffix; // user nyebut pagi/sore/pm/am
  final bool dateWasExplicit;   // user nyebut tanggal/hari spesifik

  const TimeOfDay({
    required this.hour,
    required this.minute,
    required this.hasExplicitSuffix,
    required this.dateWasExplicit,
  });
}
