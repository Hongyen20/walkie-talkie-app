import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _keyToken = 'token';
  static const _keyUserId = 'user_id';
  static const _keyUsername = 'username';
  static const _keyDisplayName = 'display_name';
  static const _keyInviteCode = 'invite_code';

  static Future<void> saveUser({
    required String token,
    required String userId,
    required String username,
    required String displayName,
    required String inviteCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyUsername, username);
    await prefs.setString(_keyDisplayName, displayName);
    await prefs.setString(_keyInviteCode, inviteCode);
  }

  static Future<Map<String, String>?> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    if (token == null) return null;
    return {
      'token': token,
      'user_id': prefs.getString(_keyUserId) ?? '',
      'username': prefs.getString(_keyUsername) ?? '',
      'display_name': prefs.getString(_keyDisplayName) ?? '',
      'invite_code': prefs.getString(_keyInviteCode) ?? '',
    };
  }

  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
