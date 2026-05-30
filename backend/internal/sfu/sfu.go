package sfu

import (
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"github.com/pion/rtp"
	"github.com/pion/webrtc/v4"
)

type Peer struct {
	ID             string
	PeerConnection *webrtc.PeerConnection
	AudioTrack     *webrtc.TrackLocalStaticRTP
	renegMu        sync.Mutex
}

type SFURoom struct {
	ID            string
	Peers         map[string]*Peer
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

func (r *SFURoom) GetPeer(peerID string) (*Peer, bool) {
	return r.getPeer(peerID)
}

func (m *Manager) GetOrCreateRoom(roomID string) *SFURoom {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	if r, ok := m.rooms[roomID]; ok {
		return r
	}
	r := &SFURoom{
		ID:    roomID,
		Peers: make(map[string]*Peer),
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

func (r *SFURoom) CreatePeer(peerID string) (*Peer, error) {
	config := webrtc.Configuration{
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
	settingEngine := webrtc.SettingEngine{}
	publicIP := os.Getenv("PUBLIC_IP")
	if publicIP != "" {
		settingEngine.SetNAT1To1IPs([]string{publicIP}, webrtc.ICECandidateTypeHost)
	}
	settingEngine.SetEphemeralUDPPortRange(10000, 60000)
	api := webrtc.NewAPI(webrtc.WithSettingEngine(settingEngine))
	pc, err := api.NewPeerConnection(config)
	if err != nil {
		return nil, err
	}

	streamID := fmt.Sprintf("%s_%d", peerID, time.Now().UnixNano())
	audioTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus},
		"audio",
		streamID,
	)
	if err != nil {
		pc.Close()
		return nil, err
	}

	peer := &Peer{
		ID:             peerID,
		PeerConnection: pc,
		AudioTrack:     audioTrack,
	}

	pc.OnTrack(func(track *webrtc.TrackRemote, receiver *webrtc.RTPReceiver) {
		log.Printf("[SFU] Got track from: %s kind: %s\n", peerID, track.Kind())
		if track.Kind() == webrtc.RTPCodecTypeAudio {
			go func() {
				for {
					pkt, _, err := track.ReadRTP()
					if err != nil {
						log.Printf("[SFU] Track %s ended\n", peerID)
						return
					}
					r.forwardRTP(peerID, pkt)
				}
			}()
		}
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

	// m-line 0: recvonly — nhận audio từ client
	if _, err := pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{
		Direction: webrtc.RTPTransceiverDirectionRecvonly,
	}); err != nil {
		pc.Close()
		return nil, err
	}

	// Snapshot existing peers TRƯỚC khi add peer mới vào room
	// Tránh race condition khi 2 peer join cùng lúc
	r.mutex.Lock()
	existingPeers := make([]*Peer, 0)
	for id, ep := range r.Peers {
		if id != peerID {
			existingPeers = append(existingPeers, ep)
		}
	}
	r.Peers[peerID] = peer
	r.mutex.Unlock()

	// Add track của existing peers vào PC mới
	for _, ep := range existingPeers {
		if _, err := pc.AddTransceiverFromTrack(
			ep.AudioTrack,
			webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionSendonly},
		); err != nil {
			log.Printf("[SFU] Error adding track of %s to new peer %s: %v\n", ep.ID, peerID, err)
		} else {
			log.Printf("[SFU] Added track of existing peer %s to new peer %s\n", ep.ID, peerID)
		}
	}

	// Add track của peer mới vào existing peers và renegotiate
	for _, ep := range existingPeers {
		epID := ep.ID
		if _, err := ep.PeerConnection.AddTransceiverFromTrack(
			audioTrack,
			webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionSendonly},
		); err != nil {
			log.Printf("[SFU] Error adding new peer track to %s: %v\n", epID, err)
			continue
		}
		log.Printf("[SFU] Added track of %s to %s — renegotiating\n", peerID, epID)

		go func(ep *Peer, epID string) {
			// renegMu serialize tất cả renegotiate cho peer này
			// tránh race condition khi 2 peer join gần cùng lúc
			ep.renegMu.Lock()
			defer ep.renegMu.Unlock()

			// Kiểm tra signaling state — phải là stable mới tạo offer được
			for i := 0; i < 20; i++ {
				if ep.PeerConnection.SignalingState() ==
					webrtc.SignalingStateStable {
					break
				}

				time.Sleep(100 * time.Millisecond)
			}

			if ep.PeerConnection.SignalingState() !=
				webrtc.SignalingStateStable {

				log.Printf(
					"[SFU] Renegotiate timeout for %s state=%s",
					epID,
					ep.PeerConnection.SignalingState(),
				)
				return
			}

			offer, err := ep.PeerConnection.CreateOffer(nil)
			if err != nil {
				log.Printf("[SFU] Renegotiate offer error for %s: %v\n", epID, err)
				return
			}
			if err := ep.PeerConnection.SetLocalDescription(offer); err != nil {
				log.Printf("[SFU] Renegotiate setLocal error for %s: %v\n", epID, err)
				return
			}
			<-webrtc.GatheringCompletePromise(ep.PeerConnection)

			r.mutex.RLock()
			cb := r.OnRenegotiate
			r.mutex.RUnlock()

			if cb != nil {
				log.Printf("[SFU] Sending renegotiate offer to %s\n", epID)
				cb(epID, ep.PeerConnection.LocalDescription().SDP)
			} else {
				log.Printf("[SFU] WARNING: OnRenegotiate nil for %s\n", epID)
			}
		}(ep, epID)
	}

	log.Printf("[SFU] Peer %s joined room %s\n", peerID, r.ID)
	return peer, nil
}

func (r *SFURoom) RemovePeer(peerID string) {
	r.mutex.Lock()
	defer r.mutex.Unlock()

	if peer, ok := r.Peers[peerID]; ok {

		peer.PeerConnection.Close()

		delete(r.Peers, peerID)

		log.Printf(
			"[SFU] Peer %s left room %s\n",
			peerID,
			r.ID,
		)
	}
}

func (r *SFURoom) forwardRTP(senderID string, packet *rtp.Packet) {

	r.mutex.RLock()
	defer r.mutex.RUnlock()

	for id, peer := range r.Peers {

		if id == senderID {
			continue
		}

		log.Printf(
			"[SFU] Forward RTP %s -> %s",
			senderID,
			id,
		)

		_ = peer.AudioTrack.WriteRTP(packet)
	}
}
func (r *SFURoom) HandleOffer(peerID string, sdp string) (string, error) {
	log.Printf("[SFU] ===== HandleOffer START peer=%s =====\n", peerID)
	if _, exists := r.getPeer(peerID); exists {
		log.Printf("[SFU] Removing old peer %s before reconnect\n", peerID)
		r.RemovePeer(peerID)
	}
	log.Printf("[SFU] STEP 1: CreatePeer\n")
	peer, err := r.CreatePeer(peerID)
	if err != nil {
		log.Printf("[SFU] STEP 1 FAILED: %v\n", err)
		return "", err
	}
	log.Printf("[SFU] STEP 1 OK\n")
	log.Printf("[SFU] STEP 2: SetRemoteDescription\n")
	if err := peer.PeerConnection.SetRemoteDescription(
		webrtc.SessionDescription{
			Type: webrtc.SDPTypeOffer,
			SDP:  sdp,
		},
	); err != nil {
		log.Printf("[SFU] STEP 2 FAILED: %v\n", err)
		return "", err
	}
	log.Printf("[SFU] STEP 2 OK\n")
	log.Printf("[SFU] STEP 3: CreateAnswer\n")
	answer, err := peer.PeerConnection.CreateAnswer(nil)
	if err != nil {

		log.Printf("[SFU] STEP 3 FAILED: %v\n", err)
		return "", err
	}
	log.Printf("[SFU] STEP 3 OK\n")
	log.Printf("[SFU] STEP 4: SetLocalDescription\n")
	if err := peer.PeerConnection.SetLocalDescription(answer); err != nil {
		log.Printf("[SFU] STEP 4 FAILED: %v\n", err)
		return "", err
	}
	log.Printf("[SFU] STEP 4 OK\n")
	log.Printf("[SFU] STEP 5: Waiting ICE Gathering\n")
	select {
	case <-webrtc.GatheringCompletePromise(peer.PeerConnection):
		log.Printf("[SFU] STEP 5 OK: ICE Gathering Complete\n")
	case <-time.After(5 * time.Second):
		log.Printf("[SFU] STEP 5 TIMEOUT: ICE Gathering > 5s\n")
	}
	localDesc := peer.PeerConnection.LocalDescription()
	if localDesc == nil {

		log.Printf("[SFU] STEP 6 FAILED: LocalDescription nil\n")
		return "", fmt.Errorf("local description nil")
	}
	log.Printf(
		"[SFU] STEP 6 OK: SDP length=%d\n",
		len(localDesc.SDP),
	)
	log.Printf(
		"[SFU] ===== HandleOffer SUCCESS peer=%s =====\n",
		peerID,
	)
	return localDesc.SDP, nil
}
func (r *SFURoom) AddICECandidate(peerID string, candidate webrtc.ICECandidateInit) error {
	peer, exists := r.getPeer(peerID)
	if !exists {
		return nil
	}
	return peer.PeerConnection.AddICECandidate(candidate)
}

func (r *SFURoom) getPeer(peerID string) (*Peer, bool) {
	r.mutex.RLock()
	defer r.mutex.RUnlock()
	peer, ok := r.Peers[peerID]
	return peer, ok
}

func (r *SFURoom) renegotiateAll() {

	r.mutex.RLock()

	peers := make([]*Peer, 0)

	for _, p := range r.Peers {
		peers = append(peers, p)
	}

	r.mutex.RUnlock()

	for _, peer := range peers {

		go func(p *Peer) {

			p.renegMu.Lock()
			defer p.renegMu.Unlock()

			if p.PeerConnection.SignalingState() !=
				webrtc.SignalingStateStable {
				return
			}

			offer, err :=
				p.PeerConnection.CreateOffer(nil)

			if err != nil {
				return
			}

			if err =
				p.PeerConnection.SetLocalDescription(
					offer,
				); err != nil {
				return
			}

			select {
			case <-webrtc.GatheringCompletePromise(
				peer.PeerConnection,
			):
				log.Println("[SFU] ICE gather complete")

			case <-time.After(5 * time.Second):
				log.Println("[SFU] ICE gather timeout")
			}

			if r.OnRenegotiate != nil {
				r.OnRenegotiate(
					p.ID,
					p.PeerConnection.
						LocalDescription().
						SDP,
				)
			}

		}(peer)
	}
}
