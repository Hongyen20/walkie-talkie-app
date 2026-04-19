import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../models/channel.dart';
import '../services/room_service.dart';
import '../services/websocket_service.dart';
import '../services/webrtc_service.dart';

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
  final _webrtcService = WebRTCService();
  List<Map<String, dynamic>> _members = [];
  List<String> _onlineUsers = [];
  bool _isTalking = false;
  bool _webrtcReady = false;
  String _talkingUser = '--';
  List<String> _activityLog = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _connectWebSocket();
    _initWebRTC();
  }

  @override
  void dispose() {
    _wsService.disconnect();
    _webrtcService.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final members = await _roomService.getMembers(
      widget.user.token,
      widget.room.id,
    );
    setState(() => _members = members);
  }

  void _connectWebSocket() {
    _wsService.onMessage = _handleMessage;
    _wsService.connect(widget.user.token, widget.room.id, widget.channel.id);
    Future.delayed(const Duration(milliseconds: 500), () {
      _wsService.send({'type': 'join'});
    });
  }

  Future<void> _initWebRTC() async {
    _webrtcService.onOffer = (targetID, offer) {
      _wsService.send({'type': 'offer', 'to': targetID, 'message': offer});
    };

    _webrtcService.onAnswer = (targetID, answer) {
      _wsService.send({'type': 'answer', 'to': targetID, 'message': answer});
    };

    _webrtcService.onIceCandidate = (targetID, candidate) {
      _wsService.send({
        'type': 'ice-candidate',
        'to': targetID,
        'message': candidate,
      });
    };

    _webrtcService.onRemoteStream = (stream) {
      print('[WebRTC] Got remote stream');
    };

    final ok = await _webrtcService.initLocalStream();
    setState(() => _webrtcReady = ok);
    if (ok) {
      _addLog('Microphone ready');
    } else {
      _addLog('Microphone access denied');
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] ?? '';
    final from = msg['from'] ?? '';

    switch (type) {
      case 'your-id':
        final myId = msg['message'] as String;
        if (!_onlineUsers.contains(myId)) {
          setState(() => _onlineUsers.add(myId));
        }
        _addLog('Connected as $myId');
        break;

      case 'online-list':
        final list = (msg['message'] as String)
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList();
        setState(() => _onlineUsers = list);
        if (list.isNotEmpty && _webrtcReady) {
          _webrtcService.callAll(list);
        }
        break;

      case 'user-joined':
        if (!_onlineUsers.contains(from)) {
          setState(() => _onlineUsers.add(from));
        }
        if (_webrtcReady) {
          _webrtcService.createOffer(from).then((offer) {
            if (offer != null) {
              _wsService.send({'type': 'offer', 'to': from, 'message': offer});
            }
          });
        }
        _addLog('$from joined');
        break;

      case 'user-left':
        setState(() => _onlineUsers.remove(from));
        _addLog('$from left');
        break;

      case 'offer':
        _webrtcService.createAnswer(from, msg['message']).then((answer) {
          if (answer != null) {
            _wsService.send({'type': 'answer', 'to': from, 'message': answer});
          }
        });
        break;

      case 'answer':
        _webrtcService.setAnswer(from, msg['message']);
        break;

      case 'ice-candidate':
        _webrtcService.addIceCandidate(from, msg['message']);
        break;

      case 'ptt-start':
        setState(() => _talkingUser = from);
        _addLog('$from is talking...');
        break;

      case 'ptt-stop':
        setState(() => _talkingUser = '--');
        break;

      case 'chat':
        _addLog('[${msg['from']}]: ${msg['message']}');
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
    _webrtcService.startTalking();
    _wsService.send({'type': 'ptt-start'});
    _addLog('You are talking...');
  }

  void _stopTalk() {
    setState(() {
      _isTalking = false;
      _talkingUser = '--';
    });
    _webrtcService.stopTalking();
    _wsService.send({'type': 'ptt-stop'});
  }

  void _showMembers() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111711),
        title: Text(
          widget.channel.name,
          style: const TextStyle(color: Color(0xFF39FF14)),
        ),
        content: _members.isEmpty
            ? const Text('No members', style: TextStyle(color: Colors.white54))
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _members.length,
                  itemBuilder: (_, i) {
                    final m = _members[i];
                    final role = m['role'] ?? '';
                    return ListTile(
                      leading: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: role == 'owner'
                                ? const Color(0xFFFFD600)
                                : const Color(0xFF3a3a3a),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: role == 'owner'
                                  ? const Color(0xFFFFD600)
                                  : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        m['display_name'] ?? m['username'] ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '@${m['username'] ?? ''}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: role == 'owner'
                                ? const Color(0xFFFFD600)
                                : const Color(0xFF3a3a3a),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          role == 'owner' ? 'Owner' : 'Member',
                          style: TextStyle(
                            color: role == 'owner'
                                ? const Color(0xFFFFD600)
                                : Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  },
                ),
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
        backgroundColor: const Color(0xFF111111),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF39FF14)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.channel.name,
              style: const TextStyle(color: Color(0xFF39FF14), fontSize: 14),
            ),
            Text(
              widget.room.name,
              style: const TextStyle(color: Color(0xFF4a6b4a), fontSize: 11),
            ),
          ],
        ),
        actions: [
          // ✅ Mic status indicator
          Icon(
            _webrtcReady ? Icons.mic : Icons.mic_off,
            color: _webrtcReady ? const Color(0xFF39FF14) : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _showMembers,
            child: const Text(
              'Members',
              style: TextStyle(color: Color(0xFF39FF14), fontSize: 12),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Online strip ──────────────────────────
          Container(
            color: const Color(0xFF0d150d),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ONLINE',
                  style: TextStyle(
                    color: Color(0xFF4a6b4a),
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                _onlineUsers.isEmpty
                    ? const Text(
                        'No one online yet',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _onlineUsers.map((name) {
                            final initial = name.isNotEmpty
                                ? name[0].toUpperCase()
                                : '?';
                            return Container(
                              margin: const EdgeInsets.only(right: 12),
                              child: Column(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF1f2e1f),
                                      border: Border.all(
                                        color: const Color(0xFF39FF14),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        initial,
                                        style: const TextStyle(
                                          color: Color(0xFF39FF14),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    name.length > 6
                                        ? '${name.substring(0, 6)}...'
                                        : name,
                                    style: const TextStyle(
                                      color: Color(0xFF39FF14),
                                      fontSize: 9,
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

          // ── Activity log ──────────────────────────
          Container(
            height: 90,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1a1a1a))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ACTIVITY',
                  style: TextStyle(
                    color: Color(0xFF4a6b4a),
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    itemCount: _activityLog.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF39FF14),
                            ),
                          ),
                          Expanded(
                            // ✅ thêm Expanded
                            child: Text(
                              _activityLog[i],
                              style: const TextStyle(
                                color: Color(0xFF4a6b4a),
                                fontSize: 11,
                              ),
                              overflow: TextOverflow
                                  .ellipsis, 
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── PTT Section ───────────────────────────
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isTalking ? 'TALKING...' : 'HOLD TO TALK',
                  style: TextStyle(
                    color: _isTalking
                        ? const Color(0xFF39FF14)
                        : const Color(0xFF4a6b4a),
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 24),

                // PTT Button
                GestureDetector(
                  onTapDown: (_) => _startTalk(),
                  onTapUp: (_) => _stopTalk(),
                  onTapCancel: () => _stopTalk(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isTalking
                          ? const Color(0xFF1a3d1a)
                          : const Color(0xFF111111),
                      border: Border.all(
                        color: _isTalking
                            ? const Color(0xFF39FF14)
                            : const Color(0xFF1f2e1f),
                        width: _isTalking ? 2.5 : 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isTalking
                                ? const Color(0xFF39FF14)
                                : const Color(0xFF1f2e1f),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'PTT',
                          style: TextStyle(
                            color: _isTalking
                                ? const Color(0xFF39FF14)
                                : const Color(0xFF4a6b4a),
                            fontSize: 11,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _statItem('${_members.length}', 'MEMBERS'),
                    Container(
                      width: 0.5,
                      height: 28,
                      color: const Color(0xFF1f2e1f),
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    _statItem('${_onlineUsers.length}', 'ONLINE'),
                    Container(
                      width: 0.5,
                      height: 28,
                      color: const Color(0xFF1f2e1f),
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    _statItem(_talkingUser, 'TALKING'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF39FF14),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4a6b4a),
            fontSize: 9,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
