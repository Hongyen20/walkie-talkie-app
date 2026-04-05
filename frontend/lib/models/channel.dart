class Channel {
  final String id;
  final String roomID;
  final String name;
  final bool isLocked;

  Channel({
    required this.id,
    required this.roomID,
    required this.name,
    required this.isLocked,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] ?? '',
      roomID: json['room_id'] ?? '',
      name: json['name'] ?? '',
      isLocked: json['is_locked'] ?? false,
    );
  }
}
