import 'dart:convert';
import 'dart:js_interop';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;
import '../config/constants.dart';

class WebRTCSFUService {
  web.RTCPeerConnection? _pc;
  web.MediaStream? _localStream;
  String? _roomId;
  String? _channelId;
  String? _token;

  Function(String)? onStatusChange;

  Future<bool> initLocalStream() async {
    try {
      final constraints = web.MediaStreamConstraints(
        audio: true.toJS,
        video: false.toJS,
      );
      _localStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      _localStream!.getAudioTracks().toDart.forEach((t) => t.enabled = false);
      print('[SFU] Mic initialized');
      return true;
    } catch (e) {
      print('[SFU] Mic error: $e');
      return false;
    }
  }

  Future<bool> connect(String token, String roomId, String channelId) async {
    _token = token;
    _roomId = roomId;
    _channelId = channelId;

    try {
      final config = web.RTCConfiguration(
        iceServers: [
          web.RTCIceServer(urls: 'stun:stun.l.google.com:19302'.toJS),
        ].toJS,
      );
      _pc = web.RTCPeerConnection(config);

      // Add local stream
      if (_localStream != null) {
        _localStream!.getTracks().toDart.forEach((track) {
          _pc!.addTrack(track, _localStream!);
        });
      }

      // Receive audio from server
      _pc!.ontrack = (web.RTCTrackEvent event) {
        print('[SFU] Got remote track!');
        final streams = event.streams.toDart;
        if (streams.isNotEmpty) {
          final audioEl = web.HTMLAudioElement();
          audioEl.srcObject = streams[0];
          audioEl.autoplay = true;
          web.document.body!.append(audioEl);
        }
      }.toJS;

      _pc!.onconnectionstatechange = (web.Event event) {
        print('[SFU] Connection state: ${_pc!.connectionState}');
        onStatusChange?.call(_pc!.connectionState ?? '');
      }.toJS;

      // Create offer
      final offer = await _pc!.createOffer().toDart;
      final offerSdp = offer?.sdp ?? '';
      await _pc!
          .setLocalDescription(
            web.RTCLocalSessionDescriptionInit(type: 'offer', sdp: offerSdp),
          )
          .toDart;

      // Send offer to server
      final res = await http.post(
        Uri.parse(
          '${Constants.baseUrl}/sfu/offer?room_id=$roomId&channel_id=$channelId',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'sdp': offerSdp}),
      );

      if (res.statusCode != 200) {
        print('[SFU] Offer failed: ${res.body}');
        return false;
      }

      final data = jsonDecode(res.body);
      // Set answer from server
      await _pc!
          .setRemoteDescription(
            web.RTCSessionDescriptionInit(sdp: data['sdp'], type: data['type']),
          )
          .toDart;

      print('[SFU] Connected to SFU server');
      return true;
    } catch (e) {
      print('[SFU] Connect error: $e');
      return false;
    }
  }

  void startTalking() {
    _localStream?.getAudioTracks().toDart.forEach((t) => t.enabled = true);
    print('[SFU] Mic ENABLED');
  }

  void stopTalking() {
    _localStream?.getAudioTracks().toDart.forEach((t) => t.enabled = false);
    print('[SFU] Mic DISABLED');
  }

  Future<void> disconnect() async {
    if (_token != null && _roomId != null && _channelId != null) {
      try {
        await http.delete(
          Uri.parse(
            '${Constants.baseUrl}/sfu/leave?room_id=$_roomId&channel_id=$_channelId',
          ),
          headers: {'Authorization': 'Bearer $_token'},
        );
      } catch (e) {
        print('[SFU] Leave error: $e');
      }
    }
    _pc?.close();
    _pc = null;

    // Remove audio elements
    final body = web.document.body;
    if (body != null) {
      final audioEls = body.querySelectorAll('audio');
      final length = audioEls.length;
      for (int i = length - 1; i >= 0; i--) {
        final el = audioEls.item(i);
        if (el != null) {
          el.parentNode?.removeChild(el);
        }
      }
    }
    print('[SFU] Disconnected');
  }

  // ✅ Handle renegotiation offer from server — only one definition
  Future<void> handleRenegotiate(String offerSdp) async {
    if (_pc == null || _token == null) return;
    print('[SFU] Handling renegotiation offer from server');
    try {
      await _pc!
          .setRemoteDescription(
            web.RTCSessionDescriptionInit(sdp: offerSdp, type: 'offer'),
          )
          .toDart;

      final answer = await _pc!.createAnswer().toDart;
      final answerSdp = answer?.sdp ?? '';
      final answerType = answer?.type ?? 'answer';

      await _pc!
          .setLocalDescription(
            web.RTCLocalSessionDescriptionInit(
              type: answerType,
              sdp: answerSdp,
            ),
          )
          .toDart;

      // Send answer back to server
      final res = await http.post(
        Uri.parse(
          '${Constants.baseUrl}/sfu/renegotiate?room_id=$_roomId&channel_id=$_channelId',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'sdp': answerSdp}),
      );
      print('[SFU] Renegotiation answer sent: ${res.statusCode}');
    } catch (e) {
      print('[SFU] Renegotiate error: $e');
    }
  }
}
