import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/user.dart';

class AuthService {
  //Save token into local storage
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  //Get token from local storage
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // Delete token when logout
  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    if (username.isEmpty) {
        return {'error': 'Please enter username'};
    }
    if (password.isEmpty) {
        return {'error': 'Please enter password'};
    }

    final res = await http.post(
        Uri.parse('${Constants.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
    );

    final data = jsonDecode(res.body);
    if (res.statusCode == 200) {
        await saveToken(data['token']);
        return {'user': User.fromJson(data, data['token'])};
    }
    return {'error': data['error']};
}

Future<Map<String, dynamic>> register(String username, String password, String displayName) async {
    final res = await http.post(
        Uri.parse('${Constants.baseUrl}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
            'username': username,
            'password': password,
            'display_name': displayName,
        }),
    );
    return jsonDecode(res.body);
}
}
