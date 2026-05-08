import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../models/channel.dart';
import '../services/room_service.dart';
import 'channel_screen.dart';

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

  static const _bg = Color(0xFFF0F4FF);
  static const _blue = Color(0xFF1A56DB);
  static const _white = Colors.white;
  static const _text = Color(0xFF111827);
  static const _textSub = Color(0xFF6B7280);

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

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? const Color(0xFFEF4444) : _blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  InputDecoration _dialogInput(String label, String hint) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _textSub, fontSize: 13),
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _blue, width: 1.5),
    ),
  );

  Future<void> _createChannel() async {
    if (widget.room.role != 'owner') return;
    final nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Create Channel',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: _text),
          decoration: _dialogInput('Channel Name', 'e.g. Construction Site A'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textSub)),
          ),
          ElevatedButton(
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
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: _white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChannel(Channel ch) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Channel',
          style: TextStyle(
            color: Color(0xFFEF4444),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Delete "${ch.name}"?',
          style: const TextStyle(color: _textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _textSub)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: _white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Delete'),
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

  Future<void> _showRoomMembers() async {
    final members = await _roomService.getMembers(
      widget.user.token,
      widget.room.id,
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${widget.room.name} — Members',
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: members.isEmpty
            ? const Text('No members yet', style: TextStyle(color: _textSub))
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: members.length,
                  itemBuilder: (_, i) {
                    final m = members[i];
                    final role = m['role'] ?? '';
                    final isOwnerMember = role == 'owner';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOwnerMember
                              ? const Color(0xFFBFD3FF)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isOwnerMember
                                  ? const Color(0xFFEEF2FF)
                                  : const Color(0xFFF3F4F6),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: isOwnerMember ? _blue : _textSub,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m['display_name'] ??
                                      m['username'] ??
                                      'Unknown',
                                  style: const TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isOwnerMember
                                  ? const Color(0xFFEEF2FF)
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isOwnerMember ? 'Owner' : 'Member',
                              style: TextStyle(
                                color: isOwnerMember ? _blue : _textSub,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (widget.room.role == 'owner' &&
                              role != 'owner') ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    backgroundColor: _white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    title: const Text(
                                      'Kick Member',
                                      style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    content: Text(
                                      'Remove "${m['display_name']}" from room?',
                                      style: const TextStyle(
                                        color: _textSub,
                                        fontSize: 14,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text(
                                          'Cancel',
                                          style: TextStyle(color: _textSub),
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFEF4444,
                                          ),
                                          foregroundColor: _white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        child: const Text('Kick'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await _roomService.kickMember(
                                    widget.user.token,
                                    widget.room.id,
                                    m['user_id'],
                                  );
                                  Navigator.pop(context);
                                  _showRoomMembers();
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Kick',
                                  style: TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: _white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Owner quản lý members của channel
  Future<void> _manageChannelMembers(Channel ch) async {
    final roomMembers = await _roomService.getMembers(
      widget.user.token,
      widget.room.id,
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        // ✅ dùng ctx thay vì _
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: _white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Manage — ${ch.name}',
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add or remove members from this channel',
                  style: TextStyle(color: _textSub, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ...roomMembers.map((m) {
                  final role = m['role'] ?? '';
                  if (role == 'owner') return const SizedBox();
                  final userId = m['user_id'] ?? '';
                  final inChannel = ch.members.contains(userId);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: inChannel
                          ? const Color(0xFFF0F4FF)
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: inChannel
                            ? const Color(0xFFBFD3FF)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: inChannel
                                ? const Color(0xFFEEF2FF)
                                : const Color(0xFFF3F4F6),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              (m['display_name'] ?? m['username'] ?? '?')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: TextStyle(
                                color: inChannel ? _blue : _textSub,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m['display_name'] ?? m['username'] ?? 'Unknown',
                                style: const TextStyle(
                                  color: _text,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            if (inChannel) {
                              await _roomService.removeChannelMember(
                                widget.user.token,
                                widget.room.id,
                                ch.id,
                                userId,
                              );
                              _showSnack(
                                '${m['display_name']} removed from channel',
                              );
                            } else {
                              await _roomService.addChannelMember(
                                widget.user.token,
                                widget.room.id,
                                ch.id,
                                userId,
                              );
                              _showSnack(
                                '${m['display_name']} added to channel',
                              );
                            }
                            Navigator.pop(
                              ctx,
                            ); // ✅ FIX: dùng ctx thay vì context
                            _loadChannels();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: inChannel
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              inChannel ? 'Remove' : 'Add',
                              style: TextStyle(
                                color: inChannel
                                    ? const Color(0xFFEF4444)
                                    : _blue,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx), // ✅ FIX: dùng ctx thay vì context
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: _white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.room.role == 'owner';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: _text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.room.name,
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          isOwner ? 'You are the owner' : 'Member',
                          style: TextStyle(
                            color: isOwner ? _blue : _textSub,
                            fontSize: 12,
                            fontWeight: isOwner
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _showRoomMembers,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            color: _blue,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Members',
                            style: TextStyle(
                              color: _blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isOwner) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _createChannel,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _blue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '+ Add',
                          style: TextStyle(
                            color: _white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Broadcast button (owner only) ────────
            if (isOwner)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A56DB), Color(0xFF3B82F6)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _blue.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.campaign_rounded, color: _white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Broadcast to Room',
                        style: TextStyle(
                          color: _white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Section title ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  const Text(
                    'Channels',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  if (_channels.isNotEmpty)
                    Text(
                      '${_channels.length} channels',
                      style: const TextStyle(color: _textSub, fontSize: 12),
                    ),
                ],
              ),
            ),

            // ── Channel list ─────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _blue))
                  : _channels.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEEF2FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.volume_up_outlined,
                              color: _blue,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No channels yet',
                            style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (isOwner)
                            const Text(
                              'Tap "+ Add" to create a channel',
                              style: TextStyle(color: _textSub, fontSize: 13),
                            ),
                          if (!isOwner)
                            const Text(
                              'You have not been added to any channel yet',
                              style: TextStyle(color: _textSub, fontSize: 13),
                            ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _channels.length,
                      itemBuilder: (_, i) {
                        final ch = _channels[i];
                        return GestureDetector(
                          onTap: ch.isLocked
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChannelScreen(
                                      user: widget.user,
                                      room: widget.room,
                                      channel: ch,
                                    ),
                                  ),
                                ),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: ch.isLocked
                                  ? const Color(0xFFFEF2F2)
                                  : _white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: ch.isLocked
                                    ? const Color(0xFFFECACA)
                                    : const Color(0xFFE5E7EB),
                              ),
                              boxShadow: ch.isLocked
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 12,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: ch.isLocked
                                        ? const Color(0xFFFEF2F2)
                                        : const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    ch.isLocked
                                        ? Icons.lock_rounded
                                        : Icons.volume_up_rounded,
                                    color: ch.isLocked
                                        ? const Color(0xFFEF4444)
                                        : _blue,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ch.name,
                                        style: TextStyle(
                                          color: ch.isLocked
                                              ? const Color(0xFFEF4444)
                                              : _text,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        ch.isLocked
                                            ? 'Locked'
                                            : '${ch.members.length} members',
                                        style: TextStyle(
                                          color: ch.isLocked
                                              ? const Color(0xFFEF4444)
                                              : _textSub,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Owner: Manage + Delete | Member: arrow
                                if (isOwner)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      GestureDetector(
                                        onTap: () => _manageChannelMembers(ch),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEEF2FF),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Text(
                                            'Manage',
                                            style: TextStyle(
                                              color: _blue,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: () => _deleteChannel(ch),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF2F2),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Text(
                                            'Delete',
                                            style: TextStyle(
                                              color: Color(0xFFEF4444),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: _textSub,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
