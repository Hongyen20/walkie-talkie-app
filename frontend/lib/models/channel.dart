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
      id: json['ID'] ?? json['id'] ?? '',
      roomID: json['RoomID'] ?? json['room_id'] ?? '',
      name: json['Name'] ?? json['name'] ?? '',
      isLocked: json['IsLocked'] ?? json['is_locked'] ?? false,
    );
  }
}
