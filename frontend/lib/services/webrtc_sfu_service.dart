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
  DateTime? _connectStartTime;

  // Mỗi remote stream có audio element riêng — tránh srcObject bị overwrite
  final Map<String, web.HTMLAudioElement> _audioElements = {};

  Function(String)? onStatusChange;

  final _renegQueue = <String>[];
  bool _renegBusy = false;

  static bool _audioUnlocked = false;
  static final List<web.HTMLAudioElement> _pendingPlay = [];

  // ─── Init mic ─────────────────────────────────────────────────────────────

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

      _audioUnlocked = true;
      _playPending();
      return true;
    } catch (e) {
      print('[SFU] Mic error: $e');
      return false;
    }
  }

  static void _playPending() {
    for (final el in List<web.HTMLAudioElement>.from(_pendingPlay)) {
      el
          .play()
          .toDart
          .then((_) {
            print('[SFU] pending play() success');
          })
          .catchError((e) {
            print('[SFU] pending play() failed: $e');
          });
    }
    _pendingPlay.clear();
  }

  // ─── Connect ──────────────────────────────────────────────────────────────

  Future<bool> connect(
    String token,
    String roomId,
    String channelId, {
    String? peerId,
  }) async {
    final startTime = DateTime.now();

    _connectStartTime = DateTime.now();

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
      final config = web.RTCConfiguration(
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
      );
      _pc = web.RTCPeerConnection(config);

      _setupOnTrack();
      _setupOnConnectionState();

      // Add local mic track (sendrecv — 1 m-line cho send + receive)
      if (_localStream != null) {
        _localStream!.getTracks().toDart.forEach((track) {
          _pc!.addTrack(track, _localStream!);
        });
      }

      // FIX: Tạo offer SDP có sẵn recvonly m-lines để server có chỗ
      // nhét track của existing peers vào.
      //
      // Cách làm: tạo 10 silent MediaStreamTrack bằng AudioContext.createMediaStreamDestination,
      // add vào PC với stream riêng biệt → browser tạo m-line sendrecv/recvonly
      // tương ứng trong offer → server map existing peer tracks vào đó →
      // ontrack fire ngay sau setRemoteDescription(answer).
      //
      // Sau khi connect, các track này bị disable → không tốn bandwidth.
      //
      // Đây là cách duy nhất không cần addTransceiver (type conflict) và
      // không cần js_interop_unsafe.
      final silentStreams = <web.MediaStream>[];
      try {
        final audioCtx = web.AudioContext();
        for (int i = 0; i < 10; i++) {
          final dest = audioCtx.createMediaStreamDestination();
          final silentStream = dest.stream;
          final tracks = silentStream.getAudioTracks().toDart;
          if (tracks.isNotEmpty) {
            _pc!.addTrack(tracks[0], silentStream);
            silentStreams.add(silentStream);
          }
        }
        // Đóng AudioContext ngay — không cần nữa sau khi đã add track
        audioCtx.close();
      } catch (e) {
        print('[SFU] Warning: could not create silent tracks: $e');
        // Không critical — renegotiate vẫn hoạt động như fallback
      }

      final offer = await _pc!.createOffer().toDart;
      final offerSdp = offer?.sdp ?? '';

      print(
        '[SFU] Offer m-lines=${_countMLines(offerSdp)} '
        '(peerId: ${peerId ?? "default"})',
      );

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

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      print('[SFU] Connection setup time = ${duration} ms');

      print('[SFU] Connected to SFU (peerId: ${peerId ?? "default"})');
      return true;
    } catch (e) {
      print('[SFU] Connect error: $e');
      return false;
    }
  }

  // ─── ontrack ──────────────────────────────────────────────────────────────

  void _setupOnTrack() {
    _pc!.ontrack = ((web.RTCTrackEvent event) {
      final streams = event.streams.toDart;
      final track = event.track;

      print(
        '[SFU] ontrack kind=${track.kind} '
        'id=${track.id} '
        'streams=${streams.length}',
      );

      // Bỏ qua track từ silent streams của chính mình
      if (track.id.startsWith('audio_') == false &&
          _localStream != null &&
          _localStream!.getTrackById(track.id) != null) {
        print('[SFU] ontrack: skip local track ${track.id}');
        return;
      }

      if (streams.isEmpty) {
        print('[SFU] ontrack: no streams — wrapping track manually');
        final stream = web.MediaStream();
        stream.addTrack(track);
        _attachAudio(stream);
        return;
      }

      // Bỏ qua nếu stream chứa track local của mình
      final stream = streams[0];
      if (_localStream != null && stream.id == _localStream!.id) {
        print('[SFU] ontrack: skip local stream');
        return;
      }

      _attachAudio(stream);
    }).toJS;
  }

  void _attachAudio(web.MediaStream stream) {
    final streamId = stream.id;

    print(
      '[SFU] Attaching audio stream=$streamId '
      'audioTracks=${stream.getAudioTracks().length}',
    );

    if (!_audioElements.containsKey(streamId)) {
      final audioEl = web.HTMLAudioElement();
      audioEl.autoplay = true;
      audioEl.muted = false;
      audioEl.volume = 1.0;
      web.document.body!.append(audioEl);
      _audioElements[streamId] = audioEl;
      print(
        '[SFU] Created audio element stream=$streamId '
        '(peerId: ${_peerId ?? "default"})',
      );
    }

    final audioEl = _audioElements[streamId]!;
    audioEl.srcObject = stream;

    print(
      '[SFU] Audio element updated '
      'muted=${audioEl.muted} volume=${audioEl.volume}',
    );

    if (_audioUnlocked) {
      _tryPlay(audioEl, streamId);
    } else {
      print('[SFU] Audio pending unlock stream=$streamId');
      if (!_pendingPlay.contains(audioEl)) {
        _pendingPlay.add(audioEl);
      }
    }
  }

  void _setupOnConnectionState() {
    _pc!.onconnectionstatechange = (web.Event event) {
      final state = _pc?.connectionState ?? '';

      if (state == 'connected' && _connectStartTime != null) {
        final duration = DateTime.now()
            .difference(_connectStartTime!)
            .inMilliseconds;

        print('[SFU] CONNECT TIME = ${duration} ms');
      }

      onStatusChange?.call(state);
    }.toJS;
  }

  // ─── PTT ──────────────────────────────────────────────────────────────────

  void startTalking() {
    _localStream?.getAudioTracks().toDart.forEach((t) {
      t.enabled = true;
      print(
        '[SFU] START TALK '
        'enabled=${t.enabled} muted=${t.muted} readyState=${t.readyState}',
      );
    });
    print('[SFU] Mic ENABLED');
  }

  void stopTalking() {
    _localStream?.getAudioTracks().toDart.forEach((t) {
      t.enabled = false;
      print(
        '[SFU] STOP TALK '
        'enabled=${t.enabled} muted=${t.muted} readyState=${t.readyState}',
      );
    });
    print('[SFU] Mic DISABLED');
  }

  // ─── Disconnect ───────────────────────────────────────────────────────────

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

    for (final el in _audioElements.values) {
      _pendingPlay.remove(el);
      try {
        el.parentNode?.removeChild(el);
      } catch (_) {}
    }
    _audioElements.clear();

    print('[SFU] Disconnected (peerId: ${_peerId ?? "default"})');
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
      if (s == 'closed' || _pc == null) {
        print('[SFU] Renegotiate aborted — PC closed');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final signalingState = _pc?.signalingState ?? 'closed';
    if (signalingState != 'stable' && signalingState != 'have-remote-offer') {
      print(
        '[SFU] Skip renegotiate — wrong state: $signalingState '
        '(peerId: ${_peerId ?? "default"})',
      );
      return;
    }

    print(
      '[SFU] Handling renegotiation state=$signalingState '
      '(peerId: ${_peerId ?? "default"})',
    );
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

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _tryPlay(web.HTMLAudioElement audioEl, String streamId) {
    audioEl
        .play()
        .toDart
        .then((_) {
          print('[SFU] play() success stream=$streamId');
        })
        .catchError((e) {
          print('[SFU] play() blocked stream=$streamId: $e');
          if (!_pendingPlay.contains(audioEl)) {
            _pendingPlay.add(audioEl);
          }
        });
  }

  int _countMLines(String sdp) {
    return RegExp(r'^m=', multiLine: true).allMatches(sdp).length;
  }
}
