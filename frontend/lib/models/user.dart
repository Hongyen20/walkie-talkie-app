import 'package:flutter/foundation.dart';

class User {
  final String id;
  final String username;
  final String displayName;
  final String inviteCode;
  final String token;


User({
  required this.id,
  required this.username,
  required this.displayName,
  required this.inviteCode,
  required this.token,
});
factory User.fromJson(Map<String, dynamic> json, String token){
  return User(
    id: json['user_id'] ?? '',
    username: json['username'] ?? '',
    displayName: json['display_name'] ?? '',
    inviteCode: json['invite_code'] ?? '',
    token: token,
  );
}
}
