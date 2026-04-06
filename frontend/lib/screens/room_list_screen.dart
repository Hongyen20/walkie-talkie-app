import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../services/room_service.dart';

class RoomListScreen extends StatefulWidget {
  final User user;
  const RoomListScreen({super.key, required this.user});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  final _roomService = RoomService();
  List<Room> _rooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);
    final rooms = await _roomService.getRooms(widget.user.token);
    setState(() {
      _rooms = rooms;
      _isLoading = false;
    });
  }

  Future<void> _createRoom() async {
    final nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111711),
        title: const Text(
          'Create Room',
          style: TextStyle(color: Color(0xFF39FF14)),
        ),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Room Name',
            labelStyle: TextStyle(color: Color(0xFF39FF14)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1f2e1f)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF39FF14)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              final room = await _roomService.createRoom(
                widget.user.token,
                nameController.text.trim(),
              );
              Navigator.pop(context);
              if (room != null) _loadRooms();
            },
            child: const Text(
              'Create',
              style: TextStyle(color: Color(0xFF39FF14)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _joinRoom() async {
    final codeController = TextEditingController();
    String? errorMsg;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF111711),
          title: const Text(
            'Join Room',
            style: TextStyle(color: Color(0xFF39FF14)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Invite Code',
                  labelStyle: TextStyle(color: Color(0xFF39FF14)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF1f2e1f)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF39FF14)),
                  ),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () async {
                if (codeController.text.trim().isEmpty) return;
                final result = await _roomService.joinRoom(
                  widget.user.token,
                  codeController.text.trim(),
                );
                if (result['room'] != null) {
                  Navigator.pop(ctx);
                  _loadRooms();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Joined room successfully!')),
                  );
                } else {
                  setStateDialog(() => errorMsg = result['error']);
                }
              },
              child: const Text(
                'Join',
                style: TextStyle(color: Color(0xFF39FF14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Hello, ${widget.user.displayName}',
          style: const TextStyle(color: Color(0xFF39FF14)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.login, color: Color(0xFF39FF14)),
            tooltip: 'Join Room',
            onPressed: _joinRoom,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF39FF14)),
            onPressed: _loadRooms,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF39FF14)),
            )
          : _rooms.isEmpty
          ? const Center(
              child: Text(
                'No rooms yet',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              itemCount: _rooms.length,
              itemBuilder: (_, i) {
                final room = _rooms[i];
                return ListTile(
                  leading: const Icon(
                    Icons.meeting_room,
                    color: Color(0xFF39FF14),
                  ),
                  title: Text(
                    room.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Code: ${room.inviteCode}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF39FF14),
                    size: 16,
                  ),
                  onTap: () {
                    // Sau này navigate sang Channel List
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF39FF14),
        foregroundColor: Colors.black,
        onPressed: _createRoom,
        child: const Icon(Icons.add),
      ),
    );
  }
}
