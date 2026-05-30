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

  Timer? _reconnectTimer;

  void connect(String token, String roomId, String channelId) {
    _lastToken = token;
    _lastRoomId = roomId;
    _lastChannelId = channelId;
    _isBroadcast = false;
    _disposed = false;
    _connect();
  }

  void connectBroadcast(String token, String roomId, String channelId) {
    _lastToken = token;
    _lastRoomId = roomId;
    _lastChannelId = channelId;
    _isBroadcast = true;
    _disposed = false;
    _connect();
  }

  void _connect() {
    _channel?.sink.close();
    _channel = null;

    final suffix = _isBroadcast ? '&broadcast=1' : '';
    final url =
        '${Constants.wsUrl}?token=$_lastToken&room_id=$_lastRoomId&channel_id=$_lastChannelId$suffix';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data);
            onMessage?.call(msg);
          } catch (_) {}
        },
        onDone: () {
          print('[WS] Disconnected');
          if (!_disposed) {
            // Auto-reconnect sau 2 giây
            _reconnectTimer?.cancel();
            _reconnectTimer = Timer(const Duration(seconds: 2), () {
              if (!_disposed) {
                print('[WS] Reconnecting...');
                _connect();
              }
            });
          }
        },
        onError: (e) {
          print('[WS] Error: $e');
          if (!_disposed) {
            _reconnectTimer?.cancel();
            _reconnectTimer = Timer(const Duration(seconds: 2), () {
              if (!_disposed) {
                print('[WS] Reconnecting after error...');
                _connect();
              }
            });
          }
        },
      );
    } catch (e) {
      print('[WS] Connect error: $e');
    }
  }

  void send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
  }
}