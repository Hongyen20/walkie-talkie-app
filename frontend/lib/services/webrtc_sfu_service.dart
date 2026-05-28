import 'dart:async';
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
  String? _peerId;

  web.HTMLAudioElement? _audioElement;
  Function(String)? onStatusChange;

  // Queue để serialize renegotiate — tránh race condition
  final _renegQueue = <String>[];
  bool _renegBusy = false;

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
      print('[SFU] Mic initialized (peerId: ${_peerId ?? "default"})');
      return true;
    } catch (e) {
      print('[SFU] Mic error: $e');
      return false;
    }
  }

  Future<bool> connect(
    String token,
    String roomId,
    String channelId, {
    String? peerId,
  }) async {
    _token = token;
    _roomId = roomId;
    _channelId = channelId;
    _peerId = peerId;
    _renegQueue.clear();
    _renegBusy = false;

    try {
      final config = web.RTCConfiguration(
        iceServers: [
          web.RTCIceServer(urls: 'stun:stun.l.google.com:19302'.toJS),
        ].toJS,
      );
      _pc = web.RTCPeerConnection(config);

      if (_localStream != null) {
        _localStream!.getTracks().toDart.forEach((track) {
          _pc!.addTrack(track, _localStream!);
        });
      }

      _pc!.ontrack = (web.RTCTrackEvent event) {
        print('[SFU] Got remote track! (peerId: ${_peerId ?? "default"})');
        final streams = event.streams.toDart;
        if (streams.isNotEmpty) {
          if (_audioElement == null) {
            _audioElement = web.HTMLAudioElement();
            _audioElement!.autoplay = true;
            web.document.body!.append(_audioElement!);
            print(
              '[SFU] Created audio element for peerId: ${_peerId ?? "default"}',
            );
          }
          _audioElement!.srcObject = streams[0];
          print(
            '[SFU] Audio stream updated for peerId: ${_peerId ?? "default"}',
          );
        }
      }.toJS;

      _pc!.onconnectionstatechange = (web.Event event) {
        final state = _pc?.connectionState ?? '';
        print(
          '[SFU] Connection state: $state (peerId: ${_peerId ?? "default"})',
        );
        onStatusChange?.call(state);
      }.toJS;

      final offer = await _pc!.createOffer().toDart;
      final offerSdp = offer?.sdp ?? '';
      await _pc!
          .setLocalDescription(
            web.RTCLocalSessionDescriptionInit(type: 'offer', sdp: offerSdp),
          )
          .toDart;

      var offerUrl =
          '${Constants.baseUrl}/sfu/offer?room_id=$roomId&channel_id=$channelId';
      if (peerId != null && peerId.isNotEmpty) {
        offerUrl += '&peer_id=$peerId';
      }

      final res = await http.post(
        Uri.parse(offerUrl),
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
      await _pc!
          .setRemoteDescription(
            web.RTCSessionDescriptionInit(sdp: data['sdp'], type: data['type']),
          )
          .toDart;

      print('[SFU] Connected to SFU (peerId: ${peerId ?? "default"})');
      return true;
    } catch (e) {
      print('[SFU] Connect error: $e');
      return false;
    }
  }

  void startTalking() {
    _localStream?.getAudioTracks().toDart.forEach((t) => t.enabled = true);
    print('[SFU] Mic ENABLED (peerId: ${_peerId ?? "default"})');
  }

  void stopTalking() {
    _localStream?.getAudioTracks().toDart.forEach((t) => t.enabled = false);
    print('[SFU] Mic DISABLED (peerId: ${_peerId ?? "default"})');
  }

  Future<void> disconnect() async {
    if (_token != null && _roomId != null && _channelId != null) {
      try {
        var leaveUrl =
            '${Constants.baseUrl}/sfu/leave?room_id=$_roomId&channel_id=$_channelId';
        if (_peerId != null && _peerId!.isNotEmpty) {
          leaveUrl += '&peer_id=$_peerId';
        }
        await http.delete(
          Uri.parse(leaveUrl),
          headers: {'Authorization': 'Bearer $_token'},
        );
      } catch (e) {
        print('[SFU] Leave error: $e');
      }
    }

    _pc?.close();
    _pc = null;
    _renegQueue.clear();
    _renegBusy = false;

    _audioElement?.parentNode?.removeChild(_audioElement!);
    _audioElement = null;

    print('[SFU] Disconnected (peerId: ${_peerId ?? "default"})');
  }

  // Queue renegotiate offers — xử lý tuần tự, không overlap
  void handleRenegotiate(String offerSdp) {
    _renegQueue.add(offerSdp);
    _processRenegQueue();
  }

  Future<void> _processRenegQueue() async {
    if (_renegBusy) return;
    _renegBusy = true;

    while (_renegQueue.isNotEmpty) {
      // Nếu có nhiều offer pending, bỏ qua các offer cũ — chỉ xử lý offer mới nhất
      final offerSdp = _renegQueue.last;
      _renegQueue.clear();

      await _doRenegotiate(offerSdp);
    }

    _renegBusy = false;
  }

  Future<void> _doRenegotiate(String offerSdp) async {
    if (_pc == null || _token == null) return;

    // FIX: kiểm tra trạng thái PC trước khi xử lý
    final signalingState = _pc!.signalingState ?? '';
    if (signalingState != 'stable' && signalingState != 'have-remote-offer') {
      print(
        '[SFU] Skip renegotiate — wrong state: $signalingState (peerId: ${_peerId ?? "default"})',
      );
      return;
    }

    print('[SFU] Handling renegotiation (peerId: ${_peerId ?? "default"})');
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

      var renegUrl =
          '${Constants.baseUrl}/sfu/renegotiate?room_id=$_roomId&channel_id=$_channelId';
      if (_peerId != null && _peerId!.isNotEmpty) {
        renegUrl += '&peer_id=$_peerId';
      }

      final res = await http.post(
        Uri.parse(renegUrl),
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
