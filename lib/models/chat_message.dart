enum MessageSender { user, bot }
enum MessageType { text, scheduleCreated, error }

class ChatMessage {
  final String text;
  final MessageSender sender;
  final MessageType type;
  final DateTime time;

  ChatMessage({
    required this.text,
    required this.sender,
    this.type = MessageType.text,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}
