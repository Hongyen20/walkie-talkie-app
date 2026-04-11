import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/room.dart';
import '../models/channel.dart';

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

  //Join room through invite code
  Future<Map<String, dynamic>> joinRoom(String token, String inviteCode) async {
    final res = await http.post(
      Uri.parse('${Constants.baseUrl}/rooms/join'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'invite_code': inviteCode}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode == 200) {
      return {'room': Room.fromJson(data)};
    }
    return {'error': data['error']};
  }

  Future<List<Channel>> getChannels(String token, String roomId) async {
    final res = await http.get(
      Uri.parse('${Constants.baseUrl}/rooms/$roomId/channels'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data == null) return [];
      final List list = data is List ? data : [];
      return list.map((e) => Channel.fromJson(e)).toList();
    }
    return [];
  }

  Future<bool> createChannel(String token, String roomId, String name) async {
    final res = await http.post(
      Uri.parse('${Constants.baseUrl}/rooms/$roomId/channels'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'name': name}),
    );
    return res.statusCode == 201;
  }

  //Delete Room
  Future<bool> deleteRoom(String token, String roomId) async {
    final res = await http.delete(
      Uri.parse('${Constants.baseUrl}/rooms/$roomId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return res.statusCode == 200;
  }

  Future<bool> deleteChannel(
    String token,
    String roomId,
    String channelId,
  ) async {
    final res = await http.delete(
      Uri.parse('${Constants.baseUrl}/rooms/$roomId/channels/$channelId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return res.statusCode == 200;
  }

  Future<bool> leaveRoom(String token, String roomId) async {
    final res = await http.delete(
      Uri.parse('${Constants.baseUrl}/rooms/$roomId/leave'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return res.statusCode == 200;
  }
}
