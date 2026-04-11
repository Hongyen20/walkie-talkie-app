import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../models/channel.dart';
import '../services/room_service.dart';

class RoomScreen extends StatefulWidget {
  final User user;
  final Room room;

  const RoomScreen({super.key, required this.user, required this.room});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final _roomService = RoomService();
  List<Channel> _channels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    setState(() => _isLoading = true);
    final channels = await _roomService.getChannels(
      widget.user.token,
      widget.room.id,
    );
    setState(() {
      _channels = channels;
      _isLoading = false;
    });
  }

  Future<void> _createChannel() async {
    if (widget.room.role != 'owner') return;
    final nameController = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111711),
        title: const Text(
          'Create Channel',
          style: TextStyle(color: Color(0xFF39FF14)),
        ),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Channel Name',
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
              await _roomService.createChannel(
                widget.user.token,
                widget.room.id,
                nameController.text.trim(),
              );
              Navigator.pop(context);
              _loadChannels();
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

  Future<void> _deleteChannel(Channel ch) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111711),
        title: const Text(
          'Delete Channel',
          style: TextStyle(color: Colors.red),
        ),
        content: Text(
          'Are you sure you want to delete "${ch.name}"?',
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
      await _roomService.deleteChannel(
        widget.user.token,
        widget.room.id,
        ch.id,
      );
      _loadChannels();
    }
  }

  void _showMembers(Channel ch) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111711),
        title: Text(ch.name, style: const TextStyle(color: Color(0xFF39FF14))),
        content: const Text(
          'Members feature coming soon...',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFF39FF14)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        // ✅ Mũi tên quay lại
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF39FF14)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.room.name,
          style: const TextStyle(color: Color(0xFF39FF14)),
        ),
        actions: [
          TextButton(
            onPressed: _loadChannels,
            child: const Text(
              'Refresh',
              style: TextStyle(color: Color(0xFF39FF14), fontSize: 13),
            ),
          ),
          if (widget.room.role == 'owner')
            TextButton(
              onPressed: _createChannel,
              child: const Text(
                'Add',
                style: TextStyle(color: Color(0xFF39FF14), fontSize: 13),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Broadcast button chỉ owner thấy
          if (widget.room.role == 'owner')
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: () {
                  // Sau này gắn WebRTC broadcast
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF39FF14),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'BROADCAST TO ROOM',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF39FF14)),
                  )
                : _channels.isEmpty
                ? const Center(
                    child: Text(
                      'No channels yet',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _channels.length,
                    itemBuilder: (_, i) {
                      final ch = _channels[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: ch.isLocked
                                ? Colors.red
                                : const Color(0xFF1f2e1f),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          title: Text(
                            ch.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            ch.isLocked ? 'Locked' : 'Active',
                            style: TextStyle(
                              color: ch.isLocked ? Colors.red : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // See member
                              if (!ch.isLocked)
                                GestureDetector(
                                  onTap: () => _showMembers(ch),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: const Color(0xFF39FF14),
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Members',
                                      style: TextStyle(
                                        color: Color(0xFF39FF14),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              if (ch.isLocked)
                                const Icon(
                                  Icons.lock,
                                  color: Colors.red,
                                  size: 16,
                                ),
                              // Delete Button
                              if (widget.room.role == 'owner') ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _deleteChannel(ch),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.red),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          onTap: ch.isLocked
                              ? null
                              : () {
                                  // Sau này navigate sang PTT Screen
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
