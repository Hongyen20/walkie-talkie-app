class Room {
  final String id;
  final String name;
  final String ownerID;
  final String inviteCode;
  final bool isActive;
  final String role;

  Room({
    required this.id,
    required this.name,
    required this.ownerID,
    required this.inviteCode,
    required this.isActive,
    this.role = '',
  });
  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['ID'] ?? json['id'] ?? '',
        name: json['Name'] ?? json['name'] ?? '',
        ownerID: json['OwnerID'] ?? json['owner_id'] ?? '',
        inviteCode: json['InvitedCode'] ?? json['invite_code'] ?? '',
        isActive: json['IsActive'] ?? json['is_active'] ?? false,
        role: json['role'] ?? '',
    );
  }
}
