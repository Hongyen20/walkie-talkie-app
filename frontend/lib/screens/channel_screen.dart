import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../models/channel.dart';
import '../services/room_service.dart';
import '../services/websocket_service.dart';
import '../services/webrtc_sfu_service.dart';

class ChannelScreen extends StatefulWidget {
  final User user;
  final Room room;
  final Channel channel;

  const ChannelScreen({
    super.key,
    required this.user,
    required this.room,
    required this.channel,
  });

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final _roomService = RoomService();
  final _wsService = WebSocketService();
  final _sfuService = WebRTCSFUService();

  // Channel members (từ DB — chỉ member được add vào channel này)
  List<Map<String, dynamic>> _channelMembers = [];
  // Online users (từ WebSocket — chỉ user đang online trong channel này)
  List<String> _onlineUsers = [];
  bool _isTalking = false;
  bool _webrtcReady = false;
  String _talkingUser = '--';
  List<String> _activityLog = [];

  static const _bg = Color(0xFFF0F4FF);
  static const _blue = Color(0xFF1A56DB);
  static const _white = Colors.white;
  static const _text = Color(0xFF111827);
  static const _textSub = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _loadChannelMembers();
    _connectWebSocket();
    _initWebRTC();
  }

  @override
  void dispose() {
    _wsService.disconnect();
    _sfuService.disconnect();
    super.dispose();
  }

  // Chỉ load members của channel này, không phải toàn room
  Future<void> _loadChannelMembers() async {
    final allRoomMembers = await _roomService.getMembers(
      widget.user.token,
      widget.room.id,
    );
    final channelMemberIds = widget.channel.members.toSet();
    print("[DEBUG] channel.members: $channelMemberIds");
    print(
      "[DEBUG] allRoomMembers user_ids: ${allRoomMembers.map((m) => m["user_id"]).toList()}",
    );
    final filtered = allRoomMembers.where((m) {
      final uid = (m["user_id"] ?? "").toString().trim();
      final role = m["role"] ?? "";
      if (role == "owner") return true;
      return channelMemberIds.any((id) => id.trim() == uid);
    }).toList();
    print(
      "[DEBUG] filtered: ${filtered.map((m) => m["display_name"]).toList()}",
    );
    setState(() => _channelMembers = filtered);
  }

  void _connectWebSocket() {
    _wsService.onMessage = _handleMessage;
    _wsService.connect(widget.user.token, widget.room.id, widget.channel.id);
    Future.delayed(const Duration(milliseconds: 500), () {
      _wsService.send({'type': 'join'});
    });
  }

  Future<void> _initWebRTC() async {
  final ok = await _sfuService.initLocalStream();
  print('[CHANNEL] initLocalStream: $ok');
  if (!ok) {
    setState(() => _webrtcReady = false);
    _addLog('Microphone access denied');
    return;
  }

  _sfuService.onStatusChange = (state) {
    print('[CHANNEL] SFU status: $state');
    if (state == 'connected') {
      setState(() => _webrtcReady = true);
      _addLog('Connected to SFU');
    } else if (state == 'failed' || state == 'disconnected') {
      setState(() => _webrtcReady = false);
      _addLog('SFU disconnected');
    }
  };

  print('[CHANNEL] Connecting to SFU room=${widget.room.id} channel=${widget.channel.id}');
  final connected = await _sfuService.connect(
    widget.user.token,
    widget.room.id,
    widget.channel.id,
  );
  print('[CHANNEL] SFU connect result: $connected');
  setState(() => _webrtcReady = connected);
  _addLog(connected ? 'Microphone ready' : 'SFU connection failed');
}

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] ?? '';
    final from = msg['from'] ?? '';

    switch (type) {
      case 'your-id':
        final myId = msg['message'] is String
            ? msg['message']
            : msg['message'].toString();
        if (!_onlineUsers.contains(myId)) {
          setState(() => _onlineUsers.add(myId));
        }
        _addLog('Connected as $myId');
        break;

      case 'online-list':
        // Backend đã filter theo channel — chỉ nhận user cùng channel
        final raw = msg['message'];
        final listStr = raw is String ? raw : raw.toString();
        final list = listStr.split(',').where((s) => s.isNotEmpty).toList();
        setState(() => _onlineUsers = list);
        break;

      case 'user-joined':
        if (!_onlineUsers.contains(from)) {
          setState(() => _onlineUsers.add(from));
        }
        _addLog('$from joined');
        break;

      case 'user-left':
        setState(() => _onlineUsers.remove(from));
        _addLog('$from left');
        break;

      case 'ptt-start':
        setState(() => _talkingUser = from);
        _addLog('$from is talking...');
        break;

      case 'ptt-stop':
        setState(() => _talkingUser = '--');
        break;

      case 'broadcast-start':
        setState(() => _talkingUser = '$from (broadcast)');
        _addLog('📢 $from is broadcasting...');
        break;

      case 'broadcast-stop':
        setState(() => _talkingUser = '--');
        _addLog('📢 Broadcast ended');
        break;

      case 'chat':
        final chatMsg = msg['message']?.toString() ?? '';
        if (!chatMsg.startsWith('{')) {
          _addLog('[${msg['from']}]: $chatMsg');
        }
        break;

      case 'sfu-renegotiate':
        final newSdp = msg['message']?.toString() ?? '';
        // channel_id cho biết renegotiate này thuộc channel nào
        // channel_screen chỉ cần xử lý nếu đúng channel của mình
        final renegChannelId = msg['channel_id']?.toString() ?? '';
        if (newSdp.isNotEmpty) {
          if (renegChannelId.isEmpty || renegChannelId == widget.channel.id) {
            _sfuService.handleRenegotiate(newSdp);
          }
          // Nếu channel_id khác → đây là renegotiate cho broadcast SFU
          // room_screen sẽ xử lý qua WebSocket của nó
        }
        break;
    }
  }

  void _addLog(String msg) {
    setState(() {
      _activityLog.insert(0, msg);
      if (_activityLog.length > 20) _activityLog.removeLast();
    });
  }

  void _startTalk() {
    if (!_webrtcReady) {
      _addLog('Microphone not ready');
      return;
    }
    setState(() {
      _isTalking = true;
      _talkingUser = widget.user.username;
    });
    _sfuService.startTalking();
    _wsService.send({'type': 'ptt-start'});
    _addLog('You are talking...');
  }

  void _stopTalk() {
    setState(() {
      _isTalking = false;
      _talkingUser = '--';
    });
    _sfuService.stopTalking();
    _wsService.send({'type': 'ptt-stop'});
  }

  void _showChannelMembers() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${widget.channel.name} — Members',
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: _channelMembers.isEmpty
            ? const Text('No members', style: TextStyle(color: _textSub))
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _channelMembers.length,
                  itemBuilder: (_, i) {
                    final m = _channelMembers[i];
                    final role = m['role'] ?? '';
                    final isOwner = role == 'owner';
                    final name =
                        m['display_name'] ?? m['username'] ?? 'Unknown';
                    final isOnline = _onlineUsers.contains(m['username'] ?? '');
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
                          color: isOwner
                              ? const Color(0xFFBFD3FF)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isOwner
                                      ? const Color(0xFFEEF2FF)
                                      : const Color(0xFFF3F4F6),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    name[0].toUpperCase(),
                                    style: TextStyle(
                                      color: isOwner ? _blue : _textSub,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              if (isOnline)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22c55e),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _white,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isOwner
                                  ? const Color(0xFFEEF2FF)
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isOwner ? 'Owner' : 'Member',
                              style: TextStyle(
                                color: isOwner ? _blue : _textSub,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
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
                          widget.channel.name,
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          widget.room.name,
                          style: const TextStyle(color: _textSub, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Mic status
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _webrtcReady
                          ? const Color(0xFFEEF2FF)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _webrtcReady
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                          size: 14,
                          color: _webrtcReady ? _blue : const Color(0xFFEF4444),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _webrtcReady ? 'Ready' : 'No mic',
                          style: TextStyle(
                            color: _webrtcReady
                                ? _blue
                                : const Color(0xFFEF4444),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showChannelMembers,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            color: _blue,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Members',
                            style: TextStyle(
                              color: _blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Online strip ──────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF22c55e),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ONLINE IN CHANNEL (${_onlineUsers.length})',
                          style: const TextStyle(
                            color: _textSub,
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _onlineUsers.isEmpty
                        ? const Text(
                            'No one online yet',
                            style: TextStyle(color: _textSub, fontSize: 12),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _onlineUsers.map((name) {
                                final initial = name.isNotEmpty
                                    ? name[0].toUpperCase()
                                    : '?';
                                final isTalking = name == _talkingUser;
                                return Container(
                                  margin: const EdgeInsets.only(right: 14),
                                  child: Column(
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isTalking
                                              ? const Color(0xFFEEF2FF)
                                              : const Color(0xFFF3F4F6),
                                          border: Border.all(
                                            color: isTalking
                                                ? _blue
                                                : const Color(0xFFE5E7EB),
                                            width: isTalking ? 2.5 : 1.5,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            initial,
                                            style: TextStyle(
                                              color: isTalking
                                                  ? _blue
                                                  : _textSub,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        name.length > 7
                                            ? '${name.substring(0, 7)}...'
                                            : name,
                                        style: TextStyle(
                                          color: isTalking ? _blue : _textSub,
                                          fontSize: 9,
                                          fontWeight: isTalking
                                              ? FontWeight.w700
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Activity log ──────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 80,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACTIVITY',
                      style: TextStyle(
                        color: _textSub,
                        fontSize: 9,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: _activityLog.isEmpty
                          ? const Text(
                              'No activity yet',
                              style: TextStyle(color: _textSub, fontSize: 11),
                            )
                          : ListView.builder(
                              reverse: true,
                              itemCount: _activityLog.length,
                              itemBuilder: (_, i) => Text(
                                _activityLog[i],
                                style: const TextStyle(
                                  color: _textSub,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // ── PTT Section ───────────────────────────
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Talking indicator
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _talkingUser != '--'
                          ? const Color(0xFFEEF2FF)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.record_voice_over_rounded,
                          size: 14,
                          color: _talkingUser != '--' ? _blue : _textSub,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _talkingUser != '--'
                              ? '$_talkingUser is talking...'
                              : 'Channel is quiet',
                          style: TextStyle(
                            color: _talkingUser != '--' ? _blue : _textSub,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // PTT Button
                  GestureDetector(
                    onTapDown: (_) => _startTalk(),
                    onTapUp: (_) => _stopTalk(),
                    onTapCancel: () => _stopTalk(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isTalking ? _blue : _white,
                        boxShadow: [
                          BoxShadow(
                            color: _isTalking
                                ? _blue.withOpacity(0.4)
                                : Colors.black.withOpacity(0.08),
                            blurRadius: _isTalking ? 24 : 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: _isTalking ? _blue : const Color(0xFFE5E7EB),
                          width: _isTalking ? 0 : 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic_rounded,
                            size: 36,
                            color: _isTalking
                                ? _white
                                : (_webrtcReady ? _blue : _textSub),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isTalking ? 'TALKING' : 'HOLD TO TALK',
                            style: TextStyle(
                              color: _isTalking
                                  ? _white
                                  : (_webrtcReady ? _blue : _textSub),
                              fontSize: 9,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Stats row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _statItem(
                          '${_channelMembers.length}',
                          'MEMBERS',
                          Icons.people_rounded,
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          color: const Color(0xFFE5E7EB),
                        ),
                        _statItem(
                          '${_onlineUsers.length}',
                          'ONLINE',
                          Icons.circle,
                          color: const Color(0xFF22c55e),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String value, String label, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color ?? _blue),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: _text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: _textSub,
            fontSize: 9,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
