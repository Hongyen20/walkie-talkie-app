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

  // FIX: Map per-stream audio elements thay vì 1 element dùng chung.
  // Khi SFU add track mới (peer thứ 2 join), ontrack fire thêm 1 lần
  // với stream mới → cần element riêng, không overwrite srcObject cũ.
  final Map<String, web.HTMLAudioElement> _audioElements = {};

  Function(String)? onStatusChange;

  final _renegQueue = <String>[];
  bool _renegBusy = false;

  // Flag để unlock audio sau user gesture (getUserMedia = gesture đủ để unlock)
  static bool _audioUnlocked = false;
  static final List<web.HTMLAudioElement> _pendingPlay = [];

  // ─── Init mic ────────────────────────────────────────────────────────────

  Future<bool> initLocalStream() async {
    try {
      final constraints = web.MediaStreamConstraints(
        audio: true.toJS,
        video: false.toJS,
      );
      _localStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;

      // Mute ngay — chỉ enable khi user nhấn PTT
      _localStream!.getAudioTracks().toDart.forEach((t) => t.enabled = false);
      print('[SFU] Mic initialized (peerId: ${_peerId ?? "default"})');

      // getUserMedia là user gesture → unlock audio autoplay
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

  // ─── Connect to SFU ──────────────────────────────────────────────────────

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

    // Đóng PC cũ nếu có
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

      // Add local mic track vào PC
      if (_localStream != null) {
        _localStream!.getTracks().toDart.forEach((track) {
          _pc!.addTrack(track, _localStream!);
        });
      }

      // FIX: Tạo audio element riêng cho từng remote stream.
      // ontrack có thể fire nhiều lần (mỗi lần 1 peer mới join room và
      // server renegotiate để gửi track đó xuống).
      // Nếu dùng 1 element duy nhất thì srcObject bị overwrite → chỉ
      // nghe được peer cuối cùng join.
      _pc!.ontrack = ((web.RTCTrackEvent event) {
        final streams = event.streams.toDart;
        final track = event.track;

        print(
          '[SFU] ontrack kind=${track.kind} '
          'id=${track.id} '
          'streams=${streams.length}',
        );

        if (streams.isEmpty) {
          print('[SFU] ontrack: no streams, skip');
          return;
        }

        final stream = streams[0];
        final streamId = stream.id;

        print(
          '[SFU] Remote stream id=$streamId '
          'audioTracks=${stream.getAudioTracks().length}',
        );

        // Tạo audio element mới cho stream này nếu chưa có
        if (!_audioElements.containsKey(streamId)) {
          final audioEl = web.HTMLAudioElement();
          audioEl.autoplay = true;
          audioEl.muted = false;
          audioEl.volume = 1.0;
          web.document.body!.append(audioEl);
          _audioElements[streamId] = audioEl;
          print(
            '[SFU] Created audio element for stream $streamId '
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
      }).toJS;

      // Connection state
      _pc!.onconnectionstatechange = (web.Event event) {
        final state = _pc?.connectionState ?? '';
        print(
          '[SFU] Connection state: $state '
          '(peerId: ${_peerId ?? "default"})',
        );
        onStatusChange?.call(state);
      }.toJS;

      // Tạo offer và gửi lên server
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

  // ─── PTT controls ────────────────────────────────────────────────────────

  void startTalking() {
    _localStream?.getAudioTracks().toDart.forEach((t) {
      t.enabled = true;
      print(
        '[SFU] START TALK '
        'enabled=${t.enabled} '
        'muted=${t.muted} '
        'readyState=${t.readyState}',
      );
    });
    print('[SFU] Mic ENABLED');
  }

  void stopTalking() {
    _localStream?.getAudioTracks().toDart.forEach((t) {
      t.enabled = false;
      print(
        '[SFU] STOP TALK '
        'enabled=${t.enabled} '
        'muted=${t.muted} '
        'readyState=${t.readyState}',
      );
    });
    print('[SFU] Mic DISABLED');
  }

  // ─── Disconnect ───────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    // Gửi leave lên server
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

    // FIX: Cleanup tất cả audio elements
    for (final entry in _audioElements.entries) {
      final el = entry.value;
      _pendingPlay.remove(el);
      try {
        el.parentNode?.removeChild(el);
      } catch (_) {}
    }
    _audioElements.clear();

    print('[SFU] Disconnected (peerId: ${_peerId ?? "default"})');
  }

  // ─── Renegotiation ────────────────────────────────────────────────────────

  /// Gọi khi nhận được sfu-renegotiate từ WebSocket.
  /// Queue để tránh race condition khi nhiều peer join gần cùng lúc.
  void handleRenegotiate(String offerSdp) {
    _renegQueue.add(offerSdp);
    _processRenegQueue();
  }

  Future<void> _processRenegQueue() async {
    if (_renegBusy) return;
    _renegBusy = true;

    while (_renegQueue.isNotEmpty) {
      // Chỉ xử lý offer mới nhất — bỏ qua các offer cũ hơn trong queue
      final offerSdp = _renegQueue.last;
      _renegQueue.clear();
      await _doRenegotiate(offerSdp);
    }

    _renegBusy = false;
  }

  Future<void> _doRenegotiate(String offerSdp) async {
    if (_pc == null || _token == null) return;

    // Chờ tối đa 5 giây cho signaling state về stable hoặc have-remote-offer
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

  // ─── Helpers ─────────────────────────────────────────────────────────────

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
}
