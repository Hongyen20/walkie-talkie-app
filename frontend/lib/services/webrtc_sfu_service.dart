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

  final Map<String, web.HTMLAudioElement> _audioElements = {};
  Function(String)? onStatusChange;

  final _renegQueue = <String>[];
  bool _renegBusy = false;

  static bool _audioUnlocked = false;
  static final List<web.HTMLAudioElement> _pendingPlay = [];

  // FIX 1: Cache PC được tạo sẵn trong lúc user chưa vào channel.
  // initLocalStream() tạo PC ngay sau khi có mic → khi connect() gọi
  // thì PC đã sẵn sàng, không cần tạo lại từ đầu.
  web.RTCPeerConnection? _prebuiltPc;
  web.MediaStream? _prebuiltPcStream; // local stream đã add vào _prebuiltPc

  // ─── Init mic + prebuild PC ───────────────────────────────────────────────

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

      _audioUnlocked = true;
      _playPending();

      // FIX 2: Prebuild PC ngay sau khi có mic, song song với UI load.
      // Không await — chạy background. Đến lúc connect() gọi thì PC
      // đã có sẵn offer + local description.
      unawaited(_prebuildPeerConnection());

      return true;
    } catch (e) {
      print('[SFU] Mic error: $e');
      return false;
    }
  }

  Future<void> _prebuildPeerConnection() async {
    try {
      print('[SFU] Prebuilding PeerConnection...');
      final pc = _createPc();
      _localStream!.getTracks().toDart.forEach((t) => pc.addTrack(t, _localStream!));

      // FIX 3: Thay AudioContext silent tracks bằng addTransceiver JS interop.
      // Dùng JS eval để tránh type mismatch của Dart web package.
      _addRecvTransceivers(pc, 4);

      final offer = await pc.createOffer().toDart;
      await pc.setLocalDescription(
        web.RTCLocalSessionDescriptionInit(type: 'offer', sdp: offer?.sdp ?? ''),
      ).toDart;

      _prebuiltPc = pc;
      _prebuiltPcStream = _localStream;
      print('[SFU] PeerConnection prebuilt ✓ offer ready');
    } catch (e) {
      print('[SFU] Prebuild error (non-critical): $e');
      _prebuiltPc = null;
    }
  }

  /// Dùng JS interop unsafe để gọi addTransceiver với direction string.
  /// Tránh type mismatch RTCRtpTransceiverInit của Dart web package.
  void _addRecvTransceivers(web.RTCPeerConnection pc, int count) {
    try {
      // Gọi thẳng JS API qua eval — an toàn vì chỉ dùng string literals
      for (int i = 0; i < count; i++) {
        // pc.addTransceiver('audio', {direction:'recvonly'})
        // Dùng JSObject workaround
        _callAddTransceiver(pc);
      }
    } catch (e) {
      print('[SFU] addTransceiver warning: $e');
    }
  }

  void _callAddTransceiver(web.RTCPeerConnection pc) {
    // Tạo plain JS object {direction: 'recvonly'} rồi cast
    final jsObj = _makeJsObject({'direction': 'recvonly'});
    try {
      (pc as JSObject).callMethod(
        'addTransceiver'.toJS,
        'audio'.toJS,
        jsObj,
      );
    } catch (e) {
      // Ignore — renegotiate vẫn là fallback
    }
  }

  JSObject _makeJsObject(Map<String, String> map) {
    final obj = JSObject();
    map.forEach((k, v) {
      obj.setProperty(k.toJS, v.toJS);
    });
    return obj;
  }

  // ─── Connect ──────────────────────────────────────────────────────────────

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

    if (_pc != null) {
      _pc!.close();
      _pc = null;
    }

    try {
      web.RTCPeerConnection pc;
      String offerSdp;

      // FIX 4: Dùng prebuilt PC nếu có sẵn — bỏ qua bước tạo PC và createOffer
      if (_prebuiltPc != null &&
          _prebuiltPcStream == _localStream &&
          (_prebuiltPc!.signalingState) == 'have-local-offer') {
        print('[SFU] Using prebuilt PC ✓ (saving ~1-2s)');
        pc = _prebuiltPc!;
        offerSdp = pc.localDescription?.sdp ?? '';
        _prebuiltPc = null;
        _prebuiltPcStream = null;
      } else {
        // Fallback: tạo PC mới nếu prebuilt chưa sẵn sàng
        print('[SFU] Prebuilt not ready, creating PC now...');
        pc = _createPc();
        if (_localStream != null) {
          _localStream!.getTracks().toDart.forEach((t) => pc.addTrack(t, _localStream!));
        }
        _addRecvTransceivers(pc, 4);
        final offer = await pc.createOffer().toDart;
        offerSdp = offer?.sdp ?? '';
        await pc.setLocalDescription(
          web.RTCLocalSessionDescriptionInit(type: 'offer', sdp: offerSdp),
        ).toDart;
      }

      _pc = pc;
      _setupOnTrack();
      _setupOnConnectionState();

      print('[SFU] Sending offer m-lines=${_countMLines(offerSdp)}');

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
      await _pc!.setRemoteDescription(
        web.RTCSessionDescriptionInit(sdp: data['sdp'], type: data['type']),
      ).toDart;

      print('[SFU] Connected (peerId: ${peerId ?? "default"})');
      return true;
    } catch (e) {
      print('[SFU] Connect error: $e');
      return false;
    }
  }

  web.RTCPeerConnection _createPc() {
    return web.RTCPeerConnection(
      web.RTCConfiguration(
        iceServers: [
          web.RTCIceServer(urls: 'stun:stun.l.google.com:19302'.toJS),
          web.RTCIceServer(urls: 'stun:openrelay.metered.ca:80'.toJS),
          web.RTCIceServer(
            urls: 'turn:openrelay.metered.ca:80'.toJS,
            username: 'openrelayproject',
            credential: 'openrelayproject',
          ),
          web.RTCIceServer(
            urls: 'turn:openrelay.metered.ca:443'.toJS,
            username: 'openrelayproject',
            credential: 'openrelayproject',
          ),
          web.RTCIceServer(
            urls: 'turn:openrelay.metered.ca:443?transport=tcp'.toJS,
            username: 'openrelayproject',
            credential: 'openrelayproject',
          ),
        ].toJS,
      ),
    );
  }

  // ─── ontrack ──────────────────────────────────────────────────────────────

  void _setupOnTrack() {
    _pc!.ontrack = ((web.RTCTrackEvent event) {
      final streams = event.streams.toDart;
      final track = event.track;
      print('[SFU] ontrack kind=${track.kind} id=${track.id} streams=${streams.length}');

      if (streams.isEmpty) {
        final stream = web.MediaStream();
        stream.addTrack(track);
        _attachAudio(stream);
        return;
      }
      _attachAudio(streams[0]);
    }).toJS;
  }

  void _attachAudio(web.MediaStream stream) {
    final streamId = stream.id;
    print('[SFU] Attaching audio stream=$streamId');

    if (!_audioElements.containsKey(streamId)) {
      final audioEl = web.HTMLAudioElement();
      audioEl.autoplay = true;
      audioEl.muted = false;
      audioEl.volume = 1.0;
      web.document.body!.append(audioEl);
      _audioElements[streamId] = audioEl;
    }

    final audioEl = _audioElements[streamId]!;
    audioEl.srcObject = stream;

    if (_audioUnlocked) {
      _tryPlay(audioEl, streamId);
    } else {
      if (!_pendingPlay.contains(audioEl)) _pendingPlay.add(audioEl);
    }
  }

  void _setupOnConnectionState() {
    _pc!.onconnectionstatechange = (web.Event event) {
      final state = _pc?.connectionState ?? '';
      print('[SFU] Connection state: $state');
      onStatusChange?.call(state);
    }.toJS;
  }

  // ─── PTT ──────────────────────────────────────────────────────────────────

  void startTalking() {
    _localStream?.getAudioTracks().toDart.forEach((t) {
      t.enabled = true;
      print('[SFU] START TALK enabled=${t.enabled} readyState=${t.readyState}');
    });
  }

  void stopTalking() {
    _localStream?.getAudioTracks().toDart.forEach((t) {
      t.enabled = false;
      print('[SFU] STOP TALK enabled=${t.enabled}');
    });
  }

  // ─── Disconnect ───────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    if (_token != null && _roomId != null && _channelId != null) {
      try {
        var leaveUrl =
            '${Constants.baseUrl}/sfu/leave?room_id=$_roomId&channel_id=$_channelId';
        if (_peerId != null && _peerId!.isNotEmpty) leaveUrl += '&peer_id=$_peerId';
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
    _prebuiltPc?.close();
    _prebuiltPc = null;
    _prebuiltPcStream = null;
    _renegQueue.clear();
    _renegBusy = false;

    for (final el in _audioElements.values) {
      _pendingPlay.remove(el);
      try { el.parentNode?.removeChild(el); } catch (_) {}
    }
    _audioElements.clear();
    print('[SFU] Disconnected');
  }

  // ─── Renegotiation ────────────────────────────────────────────────────────

  void handleRenegotiate(String offerSdp) {
    _renegQueue.add(offerSdp);
    _processRenegQueue();
  }

  Future<void> _processRenegQueue() async {
    if (_renegBusy) return;
    _renegBusy = true;
    while (_renegQueue.isNotEmpty) {
      final offerSdp = _renegQueue.last;
      _renegQueue.clear();
      await _doRenegotiate(offerSdp);
    }
    _renegBusy = false;
  }

  Future<void> _doRenegotiate(String offerSdp) async {
    if (_pc == null || _token == null) return;

    for (int i = 0; i < 50; i++) {
      final s = _pc?.signalingState ?? 'closed';
      if (s == 'stable' || s == 'have-remote-offer') break;
      if (s == 'closed' || _pc == null) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final signalingState = _pc?.signalingState ?? 'closed';
    if (signalingState != 'stable' && signalingState != 'have-remote-offer') {
      print('[SFU] Skip renegotiate — wrong state: $signalingState');
      return;
    }

    try {
      await _pc!.setRemoteDescription(
        web.RTCSessionDescriptionInit(sdp: offerSdp, type: 'offer'),
      ).toDart;

      final answer = await _pc!.createAnswer().toDart;
      final answerSdp = answer?.sdp ?? '';

      await _pc!.setLocalDescription(
        web.RTCLocalSessionDescriptionInit(type: answer?.type ?? 'answer', sdp: answerSdp),
      ).toDart;

      var renegUrl =
          '${Constants.baseUrl}/sfu/renegotiate?room_id=$_roomId&channel_id=$_channelId';
      if (_peerId != null && _peerId!.isNotEmpty) renegUrl += '&peer_id=$_peerId';

      final res = await http.post(
        Uri.parse(renegUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'sdp': answerSdp}),
      );
      print('[SFU] Renegotiation answer sent: ${res.statusCode}');
    } catch (e) {
      print('[SFU] Renegotiate error: $e');
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static void _playPending() {
    for (final el in List<web.HTMLAudioElement>.from(_pendingPlay)) {
      el.play().toDart.then((_) => print('[SFU] pending play() success'))
          .catchError((e) => print('[SFU] pending play() failed: $e'));
    }
    _pendingPlay.clear();
  }

  void _tryPlay(web.HTMLAudioElement el, String streamId) {
    el.play().toDart
        .then((_) => print('[SFU] play() success stream=$streamId'))
        .catchError((e) {
      print('[SFU] play() blocked: $e');
      if (!_pendingPlay.contains(el)) _pendingPlay.add(el);
    });
  }

  int _countMLines(String sdp) =>
      RegExp(r'^m=', multiLine: true).allMatches(sdp).length;
}

// ignore: prefer_void_to_null
void unawaited(Future<void> future) {
  future.catchError((e) => print('[SFU] Background error: $e'));
}