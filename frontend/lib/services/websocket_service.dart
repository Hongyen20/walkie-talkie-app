import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/constants.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Function(Map<String, dynamic>)? onMessage;

  String? _lastToken;
  String? _lastRoomId;
  String? _lastChannelId;
  bool _isBroadcast = false;
  bool _disposed = false;
  bool _isConnecting = false;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  void connect(String token, String roomId, String channelId) {
    _lastToken = token;
    _lastRoomId = roomId;
    _lastChannelId = channelId;
    _isBroadcast = false;
    _disposed = false;
    _reconnectAttempts = 0;
    _connect();
  }

  void connectBroadcast(String token, String roomId, String channelId) {
    _lastToken = token;
    _lastRoomId = roomId;
    _lastChannelId = channelId;
    _isBroadcast = true;
    _disposed = false;
    _reconnectAttempts = 0;
    _connect();
  }

  void _connect() {
    if (_disposed || _isConnecting) return;
    _isConnecting = true;

    _channel?.sink.close();
    _channel = null;

    final suffix = _isBroadcast ? '&broadcast=1' : '';
    final url =
        '${Constants.wsUrl}?token=$_lastToken&room_id=$_lastRoomId&channel_id=$_lastChannelId$suffix';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnecting = false;
      _reconnectAttempts = 0;

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data);
            onMessage?.call(msg);
          } catch (_) {}
        },
        onDone: () {
          print('[WS] Disconnected');
          _isConnecting = false;
          _scheduleReconnect();
        },
        onError: (e) {
          print('[WS] Error: $e');
          _isConnecting = false;
          _scheduleReconnect();
        },
      );
    } catch (e) {
      print('[WS] Connect error: $e');
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    // Exponential backoff: 2s, 4s, 8s, max 10s
    _reconnectAttempts++;
    final delay = Duration(seconds: (_reconnectAttempts * 2).clamp(2, 10));
    print(
      '[WS] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)...',
    );

    _reconnectTimer = Timer(delay, () {
      if (_disposed) return;
      _connect();
      // Gửi lại join sau khi reconnect để cập nhật online list
      if (!_isBroadcast) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!_disposed) send({'type': 'join'});
        });
      }
    });
  }

  void send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void disconnect() {
    _disposed = true;
    _isConnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
  }
}
