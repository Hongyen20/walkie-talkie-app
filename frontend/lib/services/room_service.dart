import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/room.dart';

class RoomService {
  Future<List<Room>> getRooms(String token) async {
    final res = await http.get(
        Uri.parse('${Constants.baseUrl}/rooms'),
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
        },
    );
    if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // Check Null before check phrase
        if (data == null) return [];
        final List list = data is List ? data : [];
        return list.map((e) => Room.fromJson(e)).toList();
    }
    return [];
}

  Future<Room?> createRoom(String token, String name) async {
    final res = await http.post(
      Uri.parse('${Constants.baseUrl}/rooms'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode == 201) {
      return Room.fromJson(jsonDecode(res.body));
    }
    return null;
  }
}