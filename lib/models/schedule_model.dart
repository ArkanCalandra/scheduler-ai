class ScheduleModel {
  final int id;
  final String title;
  final DateTime scheduledTime;
  final String? note;
  final int notificationId;
  final int preAlarmMinutes;
  final int? preNotificationId;

  ScheduleModel({
    required this.id,
    required this.title,
    required this.scheduledTime,
    this.note,
    required this.notificationId,
    required this.preAlarmMinutes,
    this.preNotificationId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'scheduledTime': scheduledTime.toIso8601String(),
        'note': note,
        'notificationId': notificationId,
        'preAlarmMinutes': preAlarmMinutes,
        'preNotificationId': preNotificationId,
      };

  factory ScheduleModel.fromMap(Map<String, dynamic> m) => ScheduleModel(
        id: m['id'],
        title: m['title'],
        scheduledTime: DateTime.parse(m['scheduledTime']),
        note: m['note'],
        notificationId: m['notificationId'],
        preAlarmMinutes: m['preAlarmMinutes'] ?? 5, // Default for old data
        preNotificationId: m['preNotificationId'],
      );
}
