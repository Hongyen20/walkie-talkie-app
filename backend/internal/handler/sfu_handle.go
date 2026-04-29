package handler

import (
	"encoding/json"
	"log"
	"net/http"

	"walkie-talkie-app/internal/middleware"
	"walkie-talkie-app/internal/sfu"

	"github.com/golang-jwt/jwt/v5"
	"github.com/pion/webrtc/v4"
)

type SFUHandler struct {
	manager    *sfu.Manager
	notifyFunc func(string, map[string]interface{})
}

func NewSFUHandler(manager *sfu.Manager, notifyFunc func(string, map[string]interface{})) *SFUHandler {
	return &SFUHandler{manager: manager, notifyFunc: notifyFunc}
}

// *jwt.MapClaims
func getUsernameFromContext(r *http.Request) (string, bool) {
	claims, ok := r.Context().Value(middleware.UserKey).(*jwt.MapClaims)
	if !ok {
		log.Printf("[SFU] getUsernameFromContext failed, value: %v\n",
			r.Context().Value(middleware.UserKey))
		return "", false
	}
	username, ok := (*claims)["username"].(string)
	return username, ok
}

// POST /sfu/offer?room_id=xxx&channel_id=xxx
func (h *SFUHandler) HandleOffer(w http.ResponseWriter, r *http.Request) {
	log.Printf("[SFU] HandleOffer - Authorization: %s\n", r.Header.Get("Authorization"))

	username, ok := getUsernameFromContext(r)
	log.Printf("[SFU] username=%s ok=%v\n", username, ok)
	if !ok {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	roomID := r.URL.Query().Get("room_id")
	channelID := r.URL.Query().Get("channel_id")
	if roomID == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "missing room_id"})
		return
	}
	if channelID == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "missing channel_id"})
		return
	}

	var body struct {
		SDP string `json:"sdp"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid body"})
		return
	}

	roomKey := roomID + "_" + channelID
	sfuRoom := h.manager.GetOrCreateRoom(roomKey)

	//Setup renegotiation callback
	if sfuRoom.OnRenegotiate == nil {
		sfuRoom.OnRenegotiate = func(peerID string, sdp string) {
			log.Printf("[SFU] Sending renegotiate to %s\n", peerID)
			if h.notifyFunc != nil {
				h.notifyFunc(peerID, map[string]interface{}{
					"type":    "sfu-renegotiate",
					"message": sdp,
				})
			}
		}
	}
	answerSDP, err := sfuRoom.HandleOffer(username, body.SDP)
	if err != nil {
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	WriteJSON(w, http.StatusOK, map[string]string{
		"sdp":  answerSDP,
		"type": "answer",
	})
}

// POST /sfu/ice?room_id=xxx&channel_id=xxx
func (h *SFUHandler) HandleICE(w http.ResponseWriter, r *http.Request) {
	username, ok := getUsernameFromContext(r)
	if !ok {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	roomID := r.URL.Query().Get("room_id")
	channelID := r.URL.Query().Get("channel_id")

	var body struct {
		Candidate     string `json:"candidate"`
		SDPMid        string `json:"sdpMid"`
		SDPMLineIndex uint16 `json:"sdpMLineIndex"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid body"})
		return
	}

	roomKey := roomID + "_" + channelID
	sfuRoom := h.manager.GetOrCreateRoom(roomKey)
	sfuRoom.AddICECandidate(username, webrtc.ICECandidateInit{
		Candidate:     body.Candidate,
		SDPMid:        &body.SDPMid,
		SDPMLineIndex: &body.SDPMLineIndex,
	})

	WriteJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

// DELETE /sfu/leave?room_id=xxx&channel_id=xxx
func (h *SFUHandler) HandleLeave(w http.ResponseWriter, r *http.Request) {
	username, ok := getUsernameFromContext(r)
	if !ok {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	roomID := r.URL.Query().Get("room_id")
	channelID := r.URL.Query().Get("channel_id")
	roomKey := roomID + "_" + channelID

	sfuRoom := h.manager.GetOrCreateRoom(roomKey)
	sfuRoom.RemovePeer(username)
	h.manager.CleanIfEmpty(roomKey)

	WriteJSON(w, http.StatusOK, map[string]string{"message": "left"})
}

// POST /sfu/renegotiate

func (h *SFUHandler) HandleRenegotiate(w http.ResponseWriter, r *http.Request) {
	username, ok := getUsernameFromContext(r)
	if !ok {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthozied"})
		return
	}
	roomID := r.URL.Query().Get("room_id")
	channelID := r.URL.Query().Get("channel_id")

	var body struct {
		SDP string `json:"sdp"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid body"})
		return
	}

	roomKey := roomID + "_" + channelID
	sfuRoom := h.manager.GetOrCreateRoom(roomKey)

	peer, exists := sfuRoom.GetPeer(username)
	if !exists {
		WriteJSON(w, http.StatusNotFound, map[string]string{"error": "peer not found"})
		return
	}

	if err := peer.PeerConnection.SetRemoteDescription(webrtc.SessionDescription{
		Type: webrtc.SDPTypeAnswer,
		SDP:  body.SDP,
	}); err != nil {
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	WriteJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}
