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

// Peer is representing a user in SFU
type Peer struct {
	ID             string
	PeerConnection *webrtc.PeerConnection
	AudioTrack     *webrtc.TrackLocalStaticRTP
	renegMu        sync.Mutex // serialize renegotiation to avoid race condition
}

// Room contain all peers
type SFURoom struct {
	ID    string
	Peers map[string]*Peer
	mutex sync.RWMutex
	//Add callback for notifying peer need renegotiate
	OnRenegotiate func(peerID string, sdp string)
}

// Manager manage many rooms
type Manager struct {
	rooms map[string]*SFURoom
	mutex sync.RWMutex
}

func NewManager() *Manager {
	return &Manager{
		rooms: make(map[string]*SFURoom),
	}
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

// Create new PeerConnection for 1 user
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
	// Mở port range cho ICE
	settingEngine.SetEphemeralUDPPortRange(10000, 60000)

	api := webrtc.NewAPI(webrtc.WithSettingEngine(settingEngine))
	pc, err := api.NewPeerConnection(config)
	if err != nil {
		return nil, err
	}

	// Create local audio track for forwarding to other users
	// Use unique stream ID to avoid duplicate a=msid in SDP when multiple peers join
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

	// When receiving audio from this peer → forward to all others
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
		if state == webrtc.ICEConnectionStateFailed || state == webrtc.ICEConnectionStateDisconnected {
			r.RemovePeer(peerID)
		}
	})

	// Add recvonly transceiver FIRST to receive audio from this client
	// This must be added before any sendonly transceivers to keep m-line order stable
	if _, err := pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{
		Direction: webrtc.RTPTransceiverDirectionRecvonly,
	}); err != nil {
		pc.Close()
		return nil, err
	}

	// Add peer to room
	r.mutex.Lock()
	r.Peers[peerID] = peer
	r.mutex.Unlock()

	// Add existing peers' audio tracks to this new PC as sendonly
	r.mutex.RLock()
	for id, existingPeer := range r.Peers {
		if id != peerID {
			if _, err := pc.AddTransceiverFromTrack(
				existingPeer.AudioTrack,
				webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionSendonly},
			); err != nil {
				log.Printf("[SFU] Error adding transceiver from %s to %s: %v\n", id, peerID, err)
			}
		}
	}
	r.mutex.RUnlock()

	// Add this new peer's audio track to all existing PCs
	// Use AddTransceiverFromTrack to keep m-line order consistent
	r.mutex.RLock()
	for id, existingPeer := range r.Peers {
		if id != peerID {
			if _, err := existingPeer.PeerConnection.AddTransceiverFromTrack(
				audioTrack,
				webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionSendonly},
			); err != nil {
				log.Printf("[SFU] Error adding transceiver to %s: %v\n", id, err)
				continue
			}
			log.Printf("[SFU] Added track of %s to %s — triggering renegotiate\n", peerID, id)

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
				log.Printf("[SFU] Sending renegotiate offer to %s\n", epID)
				if r.OnRenegotiate != nil {
					r.OnRenegotiate(epID, ep.PeerConnection.LocalDescription().SDP)
				} else {
					log.Printf("[SFU] WARNING: OnRenegotiate is nil!\n")
				}
			}(existingPeer, id)
		}
	}
	r.mutex.RUnlock()

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

// Forward RTP packet to all other peers
func (r *SFURoom) forwardRTP(senderID string, packet *rtp.Packet) {
	r.mutex.RLock()
	defer r.mutex.RUnlock()
	for id, peer := range r.Peers {
		if id != senderID {
			if err := peer.AudioTrack.WriteRTP(packet); err != nil {
				log.Printf("[SFU] Forward error to %s: %v\n", id, err)
			}
		}
	}
}

// Handle offer from Client
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

	// Wait ICE gathering complete
	<-webrtc.GatheringCompletePromise(peer.PeerConnection)

	return peer.PeerConnection.LocalDescription().SDP, nil
}

// Add ICE candidate
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
