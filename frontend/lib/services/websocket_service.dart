import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/constants.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Function(Map<String, dynamic>)? onMessage;

  void connect(String token, String roomId, String channelId) {
    final url =
        '${Constants.wsUrl}?token=$token&room_id=$roomId&channel_id=$channelId';
    _connect(url);
  }

  // Broadcast-only connection — không join online list, không gửi user-joined/left
  void connectBroadcast(String token, String roomId, String channelId) {
    final url =
        '${Constants.wsUrl}?token=$token&room_id=$roomId&channel_id=$channelId&broadcast=1';
    _connect(url);
  }

  void _connect(String url) {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _channel!.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data);
          onMessage?.call(msg);
        } catch (_) {}
      },
      onDone: () => print('[WS] Disconnected'),
      onError: (e) => print('[WS] Error: $e'),
    );
  }

  void send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
