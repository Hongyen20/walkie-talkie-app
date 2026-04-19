import 'dart:js_interop';
import 'package:web/web.dart' as web;

class WebRTCService {
  final Map<String, web.RTCPeerConnection> _peerConnections = {};
  web.MediaStream? _localStream;

  Function(String, Map<String, dynamic>)? onOffer;
  Function(String, Map<String, dynamic>)? onAnswer;
  Function(String, Map<String, dynamic>)? onIceCandidate;
  Function(dynamic)? onRemoteStream;

  Future<bool> initLocalStream() async {
    try {
      final constraints = web.MediaStreamConstraints(
        audio: true.toJS,
        video: false.toJS,
      );
      _localStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      // Mute ban đầu
      final tracks = _localStream!.getAudioTracks().toDart;
      for (final track in tracks) {
        track.enabled = false;
      }
      return true;
    } catch (e) {
      print('[WebRTC] Mic error: $e');
      return false;
    }
  }

  web.RTCPeerConnection _createPC(String targetID) {
    final config = web.RTCConfiguration(
      iceServers: [
        web.RTCIceServer(urls: 'stun:stun.l.google.com:19302'.toJS),
      ].toJS,
    );
    final pc = web.RTCPeerConnection(config);

    // Thêm local tracks
    if (_localStream != null) {
      final tracks = _localStream!.getTracks().toDart;
      for (final track in tracks) {
        pc.addTrack(track, _localStream!);
      }
    }

    // ICE candidate
    pc.onicecandidate = (web.RTCPeerConnectionIceEvent event) {
      final candidate = event.candidate;
      if (candidate != null) {
        onIceCandidate?.call(targetID, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    }.toJS;

    // Remote track → tạo audio element để play
    pc.ontrack = (web.RTCTrackEvent event) {
      final streams = event.streams.toDart;
      if (streams.isNotEmpty) {
        final audioEl = web.HTMLAudioElement();
        audioEl.srcObject = streams[0];
        audioEl.autoplay = true;
        web.document.body!.append(audioEl);
      }
    }.toJS;

    _peerConnections[targetID] = pc;
    return pc;
  }

  Future<Map<String, dynamic>?> createOffer(String targetID) async {
    try {
      final pc = _createPC(targetID);
      final offer = await pc.createOffer().toDart;
      final offerType = offer?.type ?? 'offer';
      final offerSdp = offer?.sdp ?? '';
      await pc
          .setLocalDescription(
            web.RTCLocalSessionDescriptionInit(type: offerType, sdp: offerSdp),
          )
          .toDart;
      return {'type': offerType, 'sdp': offerSdp};
    } catch (e) {
      print('[WebRTC] createOffer error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> createAnswer(
    String targetID,
    dynamic offerData,
  ) async {
    try {
      final pc = _createPC(targetID);
      await pc
          .setRemoteDescription(
            web.RTCSessionDescriptionInit(
              sdp: offerData['sdp']?.toString() ?? '',
              type: offerData['type']?.toString() ?? 'offer',
            ),
          )
          .toDart;
      final answer = await pc.createAnswer().toDart;
      final answerType = answer?.type ?? 'answer';
      final answerSdp = answer?.sdp ?? '';
      await pc
          .setLocalDescription(
            web.RTCLocalSessionDescriptionInit(
              type: answerType,
              sdp: answerSdp,
            ),
          )
          .toDart;
      return {'type': answerType, 'sdp': answerSdp};
    } catch (e) {
      print('[WebRTC] createAnswer error: $e');
      return null;
    }
  }

  Future<void> setAnswer(String targetID, dynamic answerData) async {
    try {
      final pc = _peerConnections[targetID];
      if (pc != null) {
        await pc
            .setRemoteDescription(
              web.RTCSessionDescriptionInit(
                sdp: answerData['sdp']?.toString() ?? '',
                type: answerData['type']?.toString() ?? 'answer',
              ),
            )
            .toDart;
      }
    } catch (e) {
      print('[WebRTC] setAnswer error: $e');
    }
  }

  Future<void> addIceCandidate(String targetID, dynamic candidateData) async {
    try {
      final pc = _peerConnections[targetID];
      if (pc != null) {
        await pc
            .addIceCandidate(
              web.RTCIceCandidateInit(
                candidate: candidateData['candidate']?.toString() ?? '',
                sdpMid: candidateData['sdpMid']?.toString() ?? '',
                sdpMLineIndex: candidateData['sdpMLineIndex'] as int? ?? 0,
              ),
            )
            .toDart;
      }
    } catch (e) {
      print('[WebRTC] addIceCandidate error: $e');
    }
  }

  void startTalking() {
    if (_localStream == null) return;
    final tracks = _localStream!.getAudioTracks().toDart;
    for (final track in tracks) {
      track.enabled = true;
    }
  }

  void stopTalking() {
    if (_localStream == null) return;
    final tracks = _localStream!.getAudioTracks().toDart;
    for (final track in tracks) {
      track.enabled = false;
    }
  }

  Future<void> callAll(List<String> targetIDs) async {
    for (final id in targetIDs) {
      final offer = await createOffer(id);
      if (offer != null) onOffer?.call(id, offer);
    }
  }

  void dispose() {
    for (final pc in _peerConnections.values) {
      pc.close();
    }
    _peerConnections.clear();
    if (_localStream != null) {
      final tracks = _localStream!.getTracks().toDart;
      for (final track in tracks) {
        track.stop();
      }
    }
  }
}
