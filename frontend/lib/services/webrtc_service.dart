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
      final tracks = _localStream!.getAudioTracks().toDart;
      for (final track in tracks) {
        track.enabled = false;
      }
      print('[WebRTC] Local stream initialized, tracks: ${tracks.length}');
      return true;
    } catch (e) {
      print('[WebRTC] Mic error: $e');
      return false;
    }
  }

  // ✅ Dùng lại PC cũ nếu đã có
  web.RTCPeerConnection _getOrCreatePC(String targetID) {
    if (_peerConnections.containsKey(targetID)) {
      print('[WebRTC] Reusing existing PC for $targetID');
      return _peerConnections[targetID]!;
    }
    return _createPC(targetID);
  }

  web.RTCPeerConnection _createPC(String targetID) {
    print('[WebRTC] Creating PC for $targetID');
    final config = web.RTCConfiguration(
      iceServers: [
        web.RTCIceServer(urls: 'stun:stun.l.google.com:19302'.toJS),
      ].toJS,
    );
    final pc = web.RTCPeerConnection(config);

    if (_localStream != null) {
      final tracks = _localStream!.getTracks().toDart;
      print('[WebRTC] Adding ${tracks.length} local tracks to PC');
      for (final track in tracks) {
        pc.addTrack(track, _localStream!);
      }
    } else {
      print('[WebRTC] WARNING: localStream is null when creating PC!');
    }

    pc.onicecandidate = (web.RTCPeerConnectionIceEvent event) {
      final candidate = event.candidate;
      if (candidate != null) {
        print(
          '[WebRTC] ICE candidate for $targetID: ${candidate.candidate?.substring(0, 30)}...',
        );
        onIceCandidate?.call(targetID, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      } else {
        print('[WebRTC] ICE gathering complete for $targetID');
      }
    }.toJS;

    pc.oniceconnectionstatechange = (web.Event event) {
      print('[WebRTC] $targetID ICE state: ${pc.iceConnectionState}');
    }.toJS;

    pc.onconnectionstatechange = (web.Event event) {
      print('[WebRTC] $targetID connection state: ${pc.connectionState}');
    }.toJS;

    pc.ontrack = (web.RTCTrackEvent event) {
      print('[WebRTC] Got remote track from $targetID!');
      final streams = event.streams.toDart;
      if (streams.isNotEmpty) {
        print('[WebRTC] Creating audio element for $targetID');
        final audioEl = web.HTMLAudioElement();
        audioEl.srcObject = streams[0];
        audioEl.autoplay = true;
        web.document.body!.append(audioEl);
        onRemoteStream?.call(streams[0]);
      }
    }.toJS;

    _peerConnections[targetID] = pc;
    return pc;
  }

  Future<Map<String, dynamic>?> createOffer(String targetID) async {
    print('[WebRTC] Creating offer for $targetID');
    try {
      // ✅ Dùng _getOrCreatePC
      final pc = _getOrCreatePC(targetID);
      final offer = await pc.createOffer().toDart;
      final offerType = offer?.type ?? 'offer';
      final offerSdp = offer?.sdp ?? '';
      print('[WebRTC] Offer created for $targetID, type=$offerType');
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
    print('[WebRTC] Creating answer for $targetID');
    try {
      // ✅ Dùng _getOrCreatePC
      final pc = _getOrCreatePC(targetID);
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
      print('[WebRTC] Answer created for $targetID, type=$answerType');
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
    print('[WebRTC] Setting answer from $targetID');
    try {
      final pc = _peerConnections[targetID];
      if (pc != null) {
        // ✅ Chỉ set nếu PC chưa ở trạng thái stable
        if (pc.signalingState != 'stable') {
          await pc
              .setRemoteDescription(
                web.RTCSessionDescriptionInit(
                  sdp: answerData['sdp']?.toString() ?? '',
                  type: answerData['type']?.toString() ?? 'answer',
                ),
              )
              .toDart;
          print('[WebRTC] Answer set for $targetID');
        } else {
          print('[WebRTC] Skip setAnswer for $targetID — already stable');
        }
      } else {
        print(
          '[WebRTC] WARNING: No PC found for $targetID when setting answer!',
        );
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
        print('[WebRTC] ICE candidate added for $targetID');
      } else {
        print('[WebRTC] WARNING: No PC found for $targetID when adding ICE!');
      }
    } catch (e) {
      print('[WebRTC] addIceCandidate error: $e');
    }
  }

  void startTalking() {
    if (_localStream == null) {
      print('[WebRTC] WARNING: localStream null on startTalking!');
      return;
    }
    final tracks = _localStream!.getAudioTracks().toDart;
    for (final track in tracks) {
      track.enabled = true;
    }
    print('[WebRTC] Mic ENABLED — talking started');
  }

  void stopTalking() {
    if (_localStream == null) return;
    final tracks = _localStream!.getAudioTracks().toDart;
    for (final track in tracks) {
      track.enabled = false;
    }
    print('[WebRTC] Mic DISABLED — talking stopped');
  }

  Future<void> callAll(List<String> targetIDs) async {
    print('[WebRTC] Calling all: $targetIDs');
    for (final id in targetIDs) {
      final offer = await createOffer(id);
      if (offer != null) onOffer?.call(id, offer);
    }
  }

  void dispose() {
    print('[WebRTC] Disposing all connections');
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
