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
	// SenderTracks: audio track của từng peer, dùng để forward cho peer khác nghe
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

func (r *SFURoom) CreatePeer(peerID string) (*Peer, error) {
	api := newWebRTCAPI()
	pc, err := api.NewPeerConnection(iceConfig())
	if err != nil {
		return nil, err
	}

	// Tạo sender track cho peer này — server sẽ write audio nhận từ peer vào đây
	// rồi forward cho tất cả peers khác nghe
	streamID := fmt.Sprintf("stream_%s_%d", peerID, time.Now().UnixNano())
	senderTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus},
		"audio_"+peerID,
		streamID,
	)
	if err != nil {
		pc.Close()
		return nil, err
	}

	peer := &Peer{
		ID:             peerID,
		PeerConnection: pc,
	}

	// Nhận audio từ client peer này
	if _, err := pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{
		Direction: webrtc.RTPTransceiverDirectionRecvonly,
	}); err != nil {
		pc.Close()
		return nil, err
	}

	// Snapshot existing peers và tracks TRƯỚC khi add peer mới
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

	// Add tất cả existing sender tracks vào PC của peer mới
	// → peer mới sẽ nghe được tất cả người đang trong room
	for _, track := range existingTracks {
		if _, err := pc.AddTransceiverFromTrack(track, webrtc.RTPTransceiverInit{
			Direction: webrtc.RTPTransceiverDirectionSendonly,
		}); err != nil {
			log.Printf("[SFU] Error adding existing track to new peer %s: %v\n", peerID, err)
		} else {
			log.Printf("[SFU] Added existing track %s to new peer %s\n", track.ID(), peerID)
		}
	}

	// Add sender track của peer mới vào PC của tất cả existing peers
	// → existing peers sẽ nghe được peer mới, cần renegotiate
	for _, ep := range existingPeers {
		epCopy := ep
		if _, err := epCopy.PeerConnection.AddTransceiverFromTrack(
			senderTrack,
			webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionSendonly},
		); err != nil {
			log.Printf("[SFU] Error adding new peer track to existing peer %s: %v\n", epCopy.ID, err)
			continue
		}
		log.Printf("[SFU] Queued renegotiate for existing peer %s\n", epCopy.ID)

		go func(ep *Peer) {
			ep.renegMu.Lock()
			defer ep.renegMu.Unlock()

			// Chờ signaling state stable
			for i := 0; i < 30; i++ {
				if ep.PeerConnection.SignalingState() == webrtc.SignalingStateStable {
					break
				}
				time.Sleep(100 * time.Millisecond)
			}
			if ep.PeerConnection.SignalingState() != webrtc.SignalingStateStable {
				log.Printf("[SFU] Renegotiate timeout for %s state=%s\n", ep.ID,
					ep.PeerConnection.SignalingState())
				return
			}

			offer, err := ep.PeerConnection.CreateOffer(nil)
			if err != nil {
				log.Printf("[SFU] Renegotiate offer error for %s: %v\n", ep.ID, err)
				return
			}
			if err := ep.PeerConnection.SetLocalDescription(offer); err != nil {
				log.Printf("[SFU] Renegotiate setLocal error for %s: %v\n", ep.ID, err)
				return
			}
			<-webrtc.GatheringCompletePromise(ep.PeerConnection)

			r.mutex.RLock()
			cb := r.OnRenegotiate
			r.mutex.RUnlock()

			if cb != nil {
				cb(ep.ID, ep.PeerConnection.LocalDescription().SDP)
			} else {
				log.Printf("[SFU] WARNING: OnRenegotiate nil for %s\n", ep.ID)
			}
		}(epCopy)
	}

	// OnTrack: nhận audio từ peer, write vào senderTrack để forward cho người khác
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
				// Write vào senderTrack của peer này
				// Tất cả peers khác đã add track này → tự nhận được audio
				if err := senderTrack.WriteRTP(pkt); err != nil {
					// Track closed — peer đã disconnect
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

	log.Printf("[SFU] Peer %s joined room %s\n", peerID, r.ID)
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

func (r *SFURoom) HandleOffer(peerID string, sdp string) (string, error) {
	log.Printf("[SFU] HandleOffer START peer=%s\n", peerID)

	if _, exists := r.GetPeer(peerID); exists {
		log.Printf("[SFU] Removing old peer %s before reconnect\n", peerID)
		r.RemovePeer(peerID)
	}

	peer, err := r.CreatePeer(peerID)
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
