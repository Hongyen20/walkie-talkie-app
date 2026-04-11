import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../services/room_service.dart';
import 'room_screen.dart';

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
    try {
      final rooms = await _roomService.getRooms(widget.user.token);
      setState(() {
        _rooms = rooms;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
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
              await _roomService.createRoom(
                widget.user.token,
                nameController.text.trim(),
              );
              Navigator.pop(context);
              _loadRooms();
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

  Future<void> _deleteRoom(Room room) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111711),
        title: const Text('Delete Room', style: TextStyle(color: Colors.red)),
        content: Text(
          'Are you sure you want to delete "${room.name}"?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF39FF14)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _roomService.deleteRoom(widget.user.token, room.id);
      _loadRooms();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false,
        title: Text(
          'Hello, ${widget.user.displayName}',
          style: const TextStyle(color: Color(0xFF39FF14), fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: _joinRoom,
            child: const Text(
              'Join',
              style: TextStyle(color: Color(0xFF39FF14), fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _createRoom,
            child: const Text(
              'Add',
              style: TextStyle(color: Color(0xFF39FF14), fontSize: 13),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF39FF14)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'MY ROOMS',
                    style: TextStyle(
                      color: Color(0xFF39FF14),
                      fontSize: 12,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: _rooms.isEmpty
                      ? const Center(
                          child: Text(
                            'No rooms yet',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _rooms.length,
                          itemBuilder: (_, i) {
                            final room = _rooms[i];
                            final isOwner = room.role == 'owner';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isOwner
                                      ? const Color(0xFF39FF14)
                                      : const Color(0xFF3a3a3a),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListTile(
                                title: Text(
                                  room.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'Code: ${room.inviteCode}',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                                // Trailing delete room button (just owner have)
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: isOwner
                                              ? const Color(0xFF39FF14)
                                              : const Color(0xFF3a3a3a),
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isOwner ? 'Owner' : 'Member',
                                        style: TextStyle(
                                          color: isOwner
                                              ? const Color(0xFF39FF14)
                                              : Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Owner have delete button, Member have Leave button
                                    if (isOwner)
                                      GestureDetector(
                                        onTap: () => _deleteRoom(room),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.red,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'Delete',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      GestureDetector(
                                        onTap: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              backgroundColor: const Color(
                                                0xFF111711,
                                              ),
                                              title: const Text(
                                                'Leave Room',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                ),
                                              ),
                                              content: Text(
                                                'Are you sure you want to leave "${room.name}"?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        false,
                                                      ),
                                                  child: const Text(
                                                    'Cancel',
                                                    style: TextStyle(
                                                      color: Color(0xFF39FF14),
                                                    ),
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        true,
                                                      ),
                                                  child: const Text(
                                                    'Leave',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await _roomService.leaveRoom(
                                              widget.user.token,
                                              room.id,
                                            );
                                            _loadRooms();
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.orange,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'Leave',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RoomScreen(
                                        user: widget.user,
                                        room: room,
                                      ),
                                    ),
                                  ).then((_) => _loadRooms());
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
