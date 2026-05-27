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
	AudioTrack     *webrtc.TrackLocalStaticRTP // track này dùng để SEND audio của peer này tới người khác
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

	// Nhận audio từ peer này → forward tới tất cả người khác
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
					//forward tới AudioTrack của NGƯỜI KHÁC (không phải của chính sender)
					r.forwardRTP(peerID, pkt)
				}
			}()
		}
	})

	pc.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		log.Printf("[SFU] %s ICE: %s\n", peerID, state)
		if state == webrtc.ICEConnectionStateFailed || state == webrtc.ICEConnectionStateDisconnected {
			r.RemovePeer(peerID)
		}
	})

	// Recvonly transceiver để nhận audio từ client này
	if _, err := pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{
		Direction: webrtc.RTPTransceiverDirectionRecvonly,
	}); err != nil {
		pc.Close()
		return nil, err
	}

	// Add peer vào room TRƯỚC khi add tracks
	r.mutex.Lock()
	r.Peers[peerID] = peer
	r.mutex.Unlock()

	// Add AudioTrack của các peer đang có vào PC của peer mới (để peer mới nghe được họ)
	r.mutex.RLock()
	for id, existingPeer := range r.Peers {
		if id != peerID {
			if _, err := pc.AddTransceiverFromTrack(
				existingPeer.AudioTrack,
				webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionSendonly},
			); err != nil {
				log.Printf("[SFU] Error adding track of %s to new peer %s: %v\n", id, peerID, err)
			} else {
				log.Printf("[SFU] Added track of existing peer %s to new peer %s\n", id, peerID)
			}
		}
	}
	r.mutex.RUnlock()

	// Add AudioTrack của peer mới vào PC của tất cả existing peers (để họ nghe được peer mới)
	r.mutex.RLock()
	existingPeers := make([]*Peer, 0)
	for id, ep := range r.Peers {
		if id != peerID {
			existingPeers = append(existingPeers, ep)
		}
	}
	r.mutex.RUnlock()

	for _, ep := range existingPeers {
		epID := ep.ID
		if _, err := ep.PeerConnection.AddTransceiverFromTrack(
			audioTrack,
			webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionSendonly},
		); err != nil {
			log.Printf("[SFU] Error adding new peer track to %s: %v\n", epID, err)
			continue
		}
		log.Printf("[SFU] Added track of new peer %s to existing peer %s — triggering renegotiate\n", peerID, epID)

		go func(ep *Peer, epID string) {
			ep.renegMu.Lock()
			defer ep.renegMu.Unlock()

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

			// FIX BUG 1: dùng r.OnRenegotiate thay vì capture lúc khởi tạo
			// vì OnRenegotiate được set SAU khi CreatePeer được gọi
			r.mutex.RLock()
			cb := r.OnRenegotiate
			r.mutex.RUnlock()

			if cb != nil {
				log.Printf("[SFU] Sending renegotiate offer to %s\n", epID)
				cb(epID, ep.PeerConnection.LocalDescription().SDP)
			} else {
				log.Printf("[SFU] WARNING: OnRenegotiate is nil for %s!\n", epID)
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
		log.Printf("[SFU] Peer %s left room %s\n", peerID, r.ID)
	}
}
func (r *SFURoom) forwardRTP(senderID string, packet *rtp.Packet) {
	r.mutex.RLock()
	sender, ok := r.Peers[senderID]
	r.mutex.RUnlock()

	if !ok {
		return
	}

	// Ghi vào AudioTrack của CHÍNH sender — đây là track mà các peer khác đang subscribe
	if err := sender.AudioTrack.WriteRTP(packet); err != nil {
		log.Printf("[SFU] Forward error writing to sender track %s: %v\n", senderID, err)
	}
}

func (r *SFURoom) HandleOffer(peerID string, sdp string) (string, error) {
	if _, exists := r.getPeer(peerID); exists {
		log.Printf("[SFU] Removing old peer %s before reconnect\n", peerID)
		r.RemovePeer(peerID)
	}

	peer, err := r.CreatePeer(peerID)
	if err != nil {
		return "", err
	}

	offer := webrtc.SessionDescription{
		Type: webrtc.SDPTypeOffer,
		SDP:  sdp,
	}
	if err := peer.PeerConnection.SetRemoteDescription(offer); err != nil {
		return "", err
	}

	answer, err := peer.PeerConnection.CreateAnswer(nil)
	if err != nil {
		return "", err
	}

	if err := peer.PeerConnection.SetLocalDescription(answer); err != nil {
		return "", err
	}

	<-webrtc.GatheringCompletePromise(peer.PeerConnection)

	return peer.PeerConnection.LocalDescription().SDP, nil
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
