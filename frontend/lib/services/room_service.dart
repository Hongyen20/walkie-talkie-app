import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/room.dart';
import '../models/channel.dart';

class RoomService {
  // =========================
  // GET ROOMS
  // =========================
  Future<List<Room>> getRooms(String token) async {
    try {
      final res = await http.get(
        Uri.parse('${Constants.baseUrl}/rooms'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print("GET ROOMS STATUS: ${res.statusCode}");
      print("GET ROOMS BODY: '${res.body}'");

      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      if (res.body.isEmpty) return [];

      final decoded = jsonDecode(res.body);
      if (decoded is! List) return [];

      return decoded.map<Room>((e) => Room.fromJson(e)).toList();
    } catch (e) {
      print("GET ROOMS ERROR: $e");
      return [];
    }
  }

  // =========================
  // CREATE ROOM
  // =========================
  Future<Map<String, dynamic>> createRoom(String token, String name) async {
    try {
      final res = await http.post(
        Uri.parse('${Constants.baseUrl}/rooms'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'name': name}),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 201) {
        return {'room': Room.fromJson(data)};
      }
      return {'error': data['error'] ?? 'Failed to create room'};
    } catch (e) {
      print("CREATE ROOM ERROR: $e");
      return {'error': e.toString()};
    }
  }

  // =========================
  // RENAME ROOM
  // =========================
  Future<Map<String, dynamic>> renameRoom(
    String token,
    String roomId,
    String newName,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('${Constants.baseUrl}/rooms/$roomId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'name': newName}),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return {'message': data['message']};
      }
      return {'error': data['error'] ?? 'Failed to rename room'};
    } catch (e) {
      print("RENAME ROOM ERROR: $e");
      return {'error': e.toString()};
    }
  }

  // =========================
  // JOIN ROOM
  // =========================
  Future<Map<String, dynamic>> joinRoom(String token, String inviteCode) async {
    try {
      final res = await http.post(
        Uri.parse('${Constants.baseUrl}/rooms/join'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'invite_code': inviteCode}),
      );

      if (res.body.isEmpty) return {'error': 'Empty response'};

      final data = jsonDecode(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {'room': Room.fromJson(data)};
      }
      return {'error': data['error'] ?? 'Unknown error'};
    } catch (e) {
      print("JOIN ROOM ERROR: $e");
      return {'error': e.toString()};
    }
  }

  // =========================
  // GET CHANNELS
  // =========================
  Future<List<Channel>> getChannels(String token, String roomId) async {
    try {
      final res = await http.get(
        Uri.parse('${Constants.baseUrl}/rooms/$roomId/channels'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      if (res.body.isEmpty) return [];

      final decoded = jsonDecode(res.body);
      if (decoded is! List) return [];

      return decoded.map<Channel>((e) => Channel.fromJson(e)).toList();
    } catch (e) {
      print("GET CHANNELS ERROR: $e");
      return [];
    }
  }

  // =========================
  // CREATE CHANNEL
  // =========================
  Future<bool> createChannel(String token, String roomId, String name) async {
    try {
      final res = await http.post(
        Uri.parse('${Constants.baseUrl}/rooms/$roomId/channels'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'name': name}),
      );
      return res.statusCode == 201;
    } catch (e) {
      print("CREATE CHANNEL ERROR: $e");
      return false;
    }
  }

  // =========================
  // DELETE ROOM
  // =========================
  Future<bool> deleteRoom(String token, String roomId) async {
    try {
      final res = await http.delete(
        Uri.parse('${Constants.baseUrl}/rooms/$roomId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return res.statusCode == 200;
    } catch (e) {
      print("DELETE ROOM ERROR: $e");
      return false;
    }
  }

  // =========================
  // DELETE CHANNEL
  // =========================
  Future<bool> deleteChannel(
    String token,
    String roomId,
    String channelId,
  ) async {
    try {
      final res = await http.delete(
        Uri.parse('${Constants.baseUrl}/rooms/$roomId/channels/$channelId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return res.statusCode == 200;
    } catch (e) {
      print("DELETE CHANNEL ERROR: $e");
      return false;
    }
  }

  // =========================
  // LEAVE ROOM
  // =========================
  Future<bool> leaveRoom(String token, String roomId) async {
    try {
      final res = await http.delete(
        Uri.parse('${Constants.baseUrl}/rooms/$roomId/leave'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return res.statusCode == 200;
    } catch (e) {
      print("LEAVE ROOM ERROR: $e");
      return false;
    }
  }

  // =========================
  // GET MEMBERS
  // =========================
  Future<List<Map<String, dynamic>>> getMembers(
    String token,
    String roomId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('${Constants.baseUrl}/rooms/$roomId/members'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      if (res.body.isEmpty) return [];

      final decoded = jsonDecode(res.body);
      if (decoded is! List) return [];

      return List<Map<String, dynamic>>.from(decoded);
    } catch (e) {
      print("GET MEMBERS ERROR: $e");
      return [];
    }
  }

  // =========================
  // KICK MEMBER
  // =========================
  Future<bool> kickMember(String token, String roomId, String userId) async {
    try {
      final res = await http.delete(
        Uri.parse('${Constants.baseUrl}/rooms/$roomId/members/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return res.statusCode == 200;
    } catch (e) {
      print("KICK MEMBER ERROR: $e");
      return false;
    }
  }

  // =========================
  // ADD CHANNEL MEMBER
  // =========================
  Future<bool> addChannelMember(
    String token,
    String roomId,
    String channelId,
    String userId,
  ) async {
    try {
      final res = await http.post(
        Uri.parse(
          '${Constants.baseUrl}/rooms/$roomId/channels/$channelId/members',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'user_id': userId}),
      );
      return res.statusCode == 200;
    } catch (e) {
      print("ADD CHANNEL MEMBER ERROR: $e");
      return false;
    }
  }

  // =========================
  // REMOVE CHANNEL MEMBER
  // =========================
  Future<bool> removeChannelMember(
    String token,
    String roomId,
    String channelId,
    String userId,
  ) async {
    try {
      final res = await http.delete(
        Uri.parse(
          '${Constants.baseUrl}/rooms/$roomId/channels/$channelId/members/$userId',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      return res.statusCode == 200;
    } catch (e) {
      print("REMOVE CHANNEL MEMBER ERROR: $e");
      return false;
    }
  }
}
