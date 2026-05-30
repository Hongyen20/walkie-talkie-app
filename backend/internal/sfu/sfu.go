package sfu

import (
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"github.com/pion/webrtc/v4"
)

type Peer struct {
	ID             string
	PeerConnection *webrtc.PeerConnection
	renegMu        sync.Mutex
}

type SFURoom struct {
	ID    string
	Peers map[string]*Peer
	// SenderTracks: audio track của từng peer.
	// Server nhận RTP từ peer, write vào track này.
	// Tất cả peer khác đã add track này vào PC của họ → tự nghe được.
	SenderTracks  map[string]*webrtc.TrackLocalStaticRTP
	mutex         sync.RWMutex
	OnRenegotiate func(peerID string, sdp string)
}

type Manager struct {
	rooms map[string]*SFURoom
	mutex sync.RWMutex
}

func NewManager() *Manager {
	return &Manager{rooms: make(map[string]*SFURoom)}
}

func (m *Manager) GetOrCreateRoom(roomID string) *SFURoom {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	if r, ok := m.rooms[roomID]; ok {
		return r
	}
	r := &SFURoom{
		ID:           roomID,
		Peers:        make(map[string]*Peer),
		SenderTracks: make(map[string]*webrtc.TrackLocalStaticRTP),
	}
	m.rooms[roomID] = r
	log.Printf("[SFU] Created room %s\n", roomID)
	return r
}

func (m *Manager) CleanIfEmpty(roomID string) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	if r, ok := m.rooms[roomID]; ok {
		r.mutex.RLock()
		count := len(r.Peers)
		r.mutex.RUnlock()
		if count == 0 {
			delete(m.rooms, roomID)
			log.Printf("[SFU] Removed empty room %s\n", roomID)
		}
	}
}

func (r *SFURoom) GetPeer(peerID string) (*Peer, bool) {
	r.mutex.RLock()
	defer r.mutex.RUnlock()
	peer, ok := r.Peers[peerID]
	return peer, ok
}

func newWebRTCAPI() *webrtc.API {
	settingEngine := webrtc.SettingEngine{}
	publicIP := os.Getenv("PUBLIC_IP")
	if publicIP != "" {
		settingEngine.SetNAT1To1IPs([]string{publicIP}, webrtc.ICECandidateTypeHost)
	}
	settingEngine.SetEphemeralUDPPortRange(10000, 60000)
	return webrtc.NewAPI(webrtc.WithSettingEngine(settingEngine))
}

func iceConfig() webrtc.Configuration {
	return webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{
			{URLs: []string{"stun:stun.l.google.com:19302"}},
			{URLs: []string{"stun:openrelay.metered.ca:80"}},
			{
				URLs:       []string{"turn:openrelay.metered.ca:80"},
				Username:   "openrelayproject",
				Credential: "openrelayproject",
			},
			{
				URLs:       []string{"turn:openrelay.metered.ca:443"},
				Username:   "openrelayproject",
				Credential: "openrelayproject",
			},
			{
				URLs:       []string{"turn:openrelay.metered.ca:443?transport=tcp"},
				Username:   "openrelayproject",
				Credential: "openrelayproject",
			},
		},
	}
}

// createSenderTrack tạo TrackLocalStaticRTP dùng để forward audio của peerID cho các peer khác.
func createSenderTrack(peerID string) (*webrtc.TrackLocalStaticRTP, error) {
	streamID := fmt.Sprintf("stream_%s_%d", peerID, time.Now().UnixNano())
	return webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus},
		"audio_"+peerID,
		streamID,
	)
}

// CreatePeer tạo peer mới, add existing tracks vào PC của peer mới,
// và renegotiate với existing peers để push track mới xuống họ.
//
// FIX race condition: callback được truyền thẳng vào hàm và capture
// vào closure ngay lúc goroutine được tạo, thay vì đọc r.OnRenegotiate
// sau một khoảng delay. Điều này đảm bảo goroutine luôn có callback
// dù HandleOffer và set OnRenegotiate xảy ra gần nhau.
func (r *SFURoom) CreatePeer(peerID string, renegCb func(string, string)) (*Peer, error) {
	api := newWebRTCAPI()
	pc, err := api.NewPeerConnection(iceConfig())
	if err != nil {
		return nil, err
	}

	senderTrack, err := createSenderTrack(peerID)
	if err != nil {
		pc.Close()
		return nil, err
	}

	peer := &Peer{
		ID:             peerID,
		PeerConnection: pc,
	}

	// recvonly transceiver — nhận audio từ client này
	if _, err := pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{
		Direction: webrtc.RTPTransceiverDirectionRecvonly,
	}); err != nil {
		pc.Close()
		return nil, err
	}

	// Snapshot existing peers + tracks TRƯỚC khi add peer mới vào room.
	// Tránh race condition khi 2 peer join gần nhau.
	r.mutex.Lock()
	existingPeers := make([]*Peer, 0, len(r.Peers))
	existingTracks := make([]*webrtc.TrackLocalStaticRTP, 0, len(r.SenderTracks))
	for id, ep := range r.Peers {
		if id != peerID {
			existingPeers = append(existingPeers, ep)
		}
	}
	for id, t := range r.SenderTracks {
		if id != peerID {
			existingTracks = append(existingTracks, t)
		}
	}
	r.Peers[peerID] = peer
	r.SenderTracks[peerID] = senderTrack
	r.mutex.Unlock()

	// Add tất cả existing sender tracks vào PC của peer mới.
	// Peer mới sẽ nghe được tất cả người đang trong room ngay sau khi connect.
	for _, track := range existingTracks {
		if _, err := pc.AddTransceiverFromTrack(track, webrtc.RTPTransceiverInit{
			Direction: webrtc.RTPTransceiverDirectionSendonly,
		}); err != nil {
			log.Printf("[SFU] Error adding existing track %s to new peer %s: %v\n",
				track.ID(), peerID, err)
		} else {
			log.Printf("[SFU] Added existing track %s to new peer %s\n", track.ID(), peerID)
		}
	}

	// Add sender track của peer mới vào PC của từng existing peer.
	// Existing peers cần renegotiate để nhận track mới này.
	for _, ep := range existingPeers {
		epCopy := ep
		if _, err := epCopy.PeerConnection.AddTransceiverFromTrack(
			senderTrack,
			webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionSendonly},
		); err != nil {
			log.Printf("[SFU] Error adding new peer track to %s: %v\n", epCopy.ID, err)
			continue
		}
		log.Printf("[SFU] Track of %s added to %s — queuing renegotiate\n", peerID, epCopy.ID)

		// FIX: renegCb được capture tại đây, không đọc r.OnRenegotiate sau delay.
		// Kể cả khi goroutine chạy muộn (vì chờ signaling stable), callback vẫn valid.
		go func(ep *Peer, cb func(string, string)) {
			ep.renegMu.Lock()
			defer ep.renegMu.Unlock()

			// Chờ signaling state stable (tối đa 3 giây)
			for i := 0; i < 30; i++ {
				if ep.PeerConnection.SignalingState() == webrtc.SignalingStateStable {
					break
				}
				time.Sleep(100 * time.Millisecond)
			}
			if ep.PeerConnection.SignalingState() != webrtc.SignalingStateStable {
				log.Printf("[SFU] Renegotiate timeout for %s state=%s\n",
					ep.ID, ep.PeerConnection.SignalingState())
				return
			}

			offer, err := ep.PeerConnection.CreateOffer(nil)
			if err != nil {
				log.Printf("[SFU] Renegotiate CreateOffer error for %s: %v\n", ep.ID, err)
				return
			}
			if err := ep.PeerConnection.SetLocalDescription(offer); err != nil {
				log.Printf("[SFU] Renegotiate SetLocalDescription error for %s: %v\n", ep.ID, err)
				return
			}
			<-webrtc.GatheringCompletePromise(ep.PeerConnection)

			if cb != nil {
				log.Printf("[SFU] Sending renegotiate offer to %s\n", ep.ID)
				cb(ep.ID, ep.PeerConnection.LocalDescription().SDP)
			} else {
				log.Printf("[SFU] WARNING: renegotiate callback nil for %s\n", ep.ID)
			}
		}(epCopy, renegCb)
	}

	// OnTrack: nhận RTP từ peer, write vào senderTrack.
	// Tất cả peer khác đã add senderTrack này vào PC của họ → tự forward.
	pc.OnTrack(func(track *webrtc.TrackRemote, receiver *webrtc.RTPReceiver) {
		log.Printf("[SFU] Got track from %s kind=%s\n", peerID, track.Kind())
		if track.Kind() != webrtc.RTPCodecTypeAudio {
			return
		}
		go func() {
			for {
				pkt, _, err := track.ReadRTP()
				if err != nil {
					log.Printf("[SFU] Track ended for %s\n", peerID)
					return
				}
				if err := senderTrack.WriteRTP(pkt); err != nil {
					return
				}
			}
		}()
	})

	pc.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		log.Printf("[SFU] %s ICE: %s\n", peerID, state)
		if state == webrtc.ICEConnectionStateDisconnected {
			go func() {
				time.Sleep(15 * time.Second)
				if pc.ICEConnectionState() == webrtc.ICEConnectionStateDisconnected {
					r.RemovePeer(peerID)
				}
			}()
		}
	})

	log.Printf("[SFU] Peer %s joined room %s (%d existing peers)\n",
		peerID, r.ID, len(existingPeers))
	return peer, nil
}

func (r *SFURoom) RemovePeer(peerID string) {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	if peer, ok := r.Peers[peerID]; ok {
		peer.PeerConnection.Close()
		delete(r.Peers, peerID)
		delete(r.SenderTracks, peerID)
		log.Printf("[SFU] Peer %s left room %s\n", peerID, r.ID)
	}
}

// HandleOffer xử lý SDP offer từ client.
// renegCb được truyền vào và capture vào goroutine ngay lập tức,
// không phụ thuộc vào r.OnRenegotiate được set sau đó.
func (r *SFURoom) HandleOffer(peerID string, sdp string, renegCb func(string, string)) (string, error) {
	log.Printf("[SFU] HandleOffer START peer=%s\n", peerID)

	// Xóa peer cũ nếu reconnect
	if _, exists := r.GetPeer(peerID); exists {
		log.Printf("[SFU] Removing old peer %s before reconnect\n", peerID)
		r.RemovePeer(peerID)
	}

	peer, err := r.CreatePeer(peerID, renegCb)
	if err != nil {
		return "", fmt.Errorf("CreatePeer: %w", err)
	}

	if err := peer.PeerConnection.SetRemoteDescription(webrtc.SessionDescription{
		Type: webrtc.SDPTypeOffer,
		SDP:  sdp,
	}); err != nil {
		return "", fmt.Errorf("SetRemoteDescription: %w", err)
	}

	answer, err := peer.PeerConnection.CreateAnswer(nil)
	if err != nil {
		return "", fmt.Errorf("CreateAnswer: %w", err)
	}

	if err := peer.PeerConnection.SetLocalDescription(answer); err != nil {
		return "", fmt.Errorf("SetLocalDescription: %w", err)
	}

	select {
	case <-webrtc.GatheringCompletePromise(peer.PeerConnection):
		log.Printf("[SFU] ICE gathering complete for %s\n", peerID)
	case <-time.After(5 * time.Second):
		log.Printf("[SFU] ICE gathering timeout for %s\n", peerID)
	}

	localDesc := peer.PeerConnection.LocalDescription()
	if localDesc == nil {
		return "", fmt.Errorf("local description nil")
	}

	log.Printf("[SFU] HandleOffer SUCCESS peer=%s sdpLen=%d\n", peerID, len(localDesc.SDP))
	return localDesc.SDP, nil
}

func (r *SFURoom) AddICECandidate(peerID string, candidate webrtc.ICECandidateInit) error {
	peer, exists := r.GetPeer(peerID)
	if !exists {
		return nil
	}
	return peer.PeerConnection.AddICECandidate(candidate)
}
