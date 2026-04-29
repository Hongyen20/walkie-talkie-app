package sfu

import (
	"log"
	"sync"

	"github.com/pion/rtp"
	"github.com/pion/webrtc/v4"
)

// Peer is representing a user in SFU
type Peer struct {
	ID             string
	PeerConnection *webrtc.PeerConnection
	AudioTrack     *webrtc.TrackLocalStaticRTP
}

// Room contain all peers
type SFURoom struct {
	ID    string
	Peers map[string]*Peer
	mutex sync.RWMutex
	//Add callback for notifying peer need renegotiate
	OnRenegotiate func(peerID string, sdp string)
}

// Manger manage many rooms
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

	pc, err := webrtc.NewPeerConnection(config)
	if err != nil {
		return nil, err
	}

	// Create local audio track for forward to another user
	audioTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus},
		"audio",
		peerID,
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

	// When user receives audio from this peer -> forward for all other user
	pc.OnTrack(func(track *webrtc.TrackRemote, receiver *webrtc.RTPReceiver) {
		log.Printf("[SFU] Got track from: %s kind: %s\n", peerID, track.Kind())
		if track.Kind() == webrtc.RTPCodecTypeAudio {
			go func() {
				for {
					rtp, _, err := track.ReadRTP()
					if err != nil {
						log.Printf("[SFU] Track %s ended\n", peerID)
						return
					}
					// Forward to all other Peer in room
					r.forwardRTP(peerID, rtp)
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

	// Add peer to room first
	r.mutex.Lock()
	r.Peers[peerID] = peer
	r.mutex.Unlock()

	// Add audio tracks of other peers into this new PC
	r.mutex.RLock()
	for id, existingPeer := range r.Peers {
		if id != peerID {
			if _, err := pc.AddTrack(existingPeer.AudioTrack); err != nil {
				log.Printf("[SFU] Error adding track from %s to %s: %v\n", id, peerID, err)
			}
		}
	}
	r.mutex.RUnlock()

	// Add track of new peer into all old PCs
	r.mutex.RLock()
	for id, existingPeer := range r.Peers {
		if id != peerID {
			if _, err := existingPeer.PeerConnection.AddTrack(audioTrack); err != nil {
				log.Printf("[SFU] Error adding new track to %s: %v\n", id, err)
				continue
			}
			log.Printf("[SFU] Added track of %s to %s — triggering renegotiate\n", peerID, id)
			go func(ep *Peer, epID string) {
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

// Forward RTP packet to all another peer
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
	//Delete old peer if this peer already existed when create new
	if _, exists := r.getPeer(peerID); exists {
		log.Printf("[SFU] Removing old peer %s before reconnect \n", peerID)
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

	//Wait ICe gathering complete
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
