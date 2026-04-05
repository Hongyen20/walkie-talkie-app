class Room {
  final String id;
  final String name;
  final String ownerID;
  final String inviteCode;
  final bool isActive;

  Room({
    required this.id,
    required this.name,
    required this.ownerID,
    required this.inviteCode,
    required this.isActive,
  });
  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      ownerID: json['owner_id'] ?? '',
      inviteCode: json['invite_code'] ?? '',
      isActive: json['is_active'] ?? false,
    );
  }
}
