package handler

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"

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

func resolvePeerID(r *http.Request, username string) string {
	peerID := r.URL.Query().Get("peer_id")
	if peerID != "" {
		return peerID
	}
	return username
}

// buildRenegCb tạo callback renegotiate cho một channel cụ thể.
// Callback này được tạo TRƯỚC khi HandleOffer chạy và truyền thẳng
// vào CreatePeer → goroutine capture ngay → không còn race condition.
func (h *SFUHandler) buildRenegCb(channelID string) func(string, string) {
	return func(peerID string, sdp string) {
		if h.notifyFunc == nil {
			return
		}
		wsTarget := strings.TrimSuffix(peerID, "_broadcast")
		isBroadcast := strings.HasSuffix(peerID, "_broadcast")
		log.Printf("[SFU] Renegotiate -> wsTarget=%s peerID=%s channel=%s\n",
			wsTarget, peerID, channelID)
		h.notifyFunc(wsTarget, map[string]interface{}{
			"type":         "sfu-renegotiate",
			"message":      sdp,
			"channel_id":   channelID,
			"is_broadcast": isBroadcast,
		})
	}
}

// POST /sfu/offer
func (h *SFUHandler) HandleOffer(w http.ResponseWriter, r *http.Request) {
	username, ok := getUsernameFromContext(r)
	if !ok {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	roomID := r.URL.Query().Get("room_id")
	channelID := r.URL.Query().Get("channel_id")
	if roomID == "" || channelID == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "missing room_id or channel_id"})
		return
	}

	peerID := resolvePeerID(r, username)
	log.Printf("[SFU] HandleOffer username=%s peerID=%s\n", username, peerID)

	var body struct {
		SDP string `json:"sdp"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid body"})
		return
	}

	roomKey := roomID + "_" + channelID
	sfuRoom := h.manager.GetOrCreateRoom(roomKey)

	// FIX: Tạo callback TRƯỚC khi gọi HandleOffer.
	// HandleOffer → CreatePeer → goroutine renegotiate capture cb ngay tại đây.
	// Không còn window thời gian giữa "set OnRenegotiate" và "goroutine chạy".
	renegCb := h.buildRenegCb(channelID)

	// Cũng set r.OnRenegotiate để tương thích với các code path khác nếu có.
	sfuRoom.OnRenegotiate = renegCb

	answerSDP, err := sfuRoom.HandleOffer(peerID, body.SDP, renegCb)
	if err != nil {
		log.Printf("[SFU] HandleOffer error for %s: %v\n", peerID, err)
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	WriteJSON(w, http.StatusOK, map[string]string{
		"sdp":  answerSDP,
		"type": "answer",
	})
}

// POST /sfu/ice
func (h *SFUHandler) HandleICE(w http.ResponseWriter, r *http.Request) {
	username, ok := getUsernameFromContext(r)
	if !ok {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	roomID := r.URL.Query().Get("room_id")
	channelID := r.URL.Query().Get("channel_id")
	peerID := resolvePeerID(r, username)

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
	sfuRoom.AddICECandidate(peerID, webrtc.ICECandidateInit{
		Candidate:     body.Candidate,
		SDPMid:        &body.SDPMid,
		SDPMLineIndex: &body.SDPMLineIndex,
	})

	WriteJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

// DELETE /sfu/leave
func (h *SFUHandler) HandleLeave(w http.ResponseWriter, r *http.Request) {
	username, ok := getUsernameFromContext(r)
	if !ok {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	roomID := r.URL.Query().Get("room_id")
	channelID := r.URL.Query().Get("channel_id")
	peerID := resolvePeerID(r, username)
	roomKey := roomID + "_" + channelID

	sfuRoom := h.manager.GetOrCreateRoom(roomKey)
	sfuRoom.RemovePeer(peerID)
	h.manager.CleanIfEmpty(roomKey)

	WriteJSON(w, http.StatusOK, map[string]string{"message": "left"})
}

// POST /sfu/renegotiate
func (h *SFUHandler) HandleRenegotiate(w http.ResponseWriter, r *http.Request) {
	username, ok := getUsernameFromContext(r)
	if !ok {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	roomID := r.URL.Query().Get("room_id")
	channelID := r.URL.Query().Get("channel_id")
	peerID := resolvePeerID(r, username)

	var body struct {
		SDP string `json:"sdp"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid body"})
		return
	}

	roomKey := roomID + "_" + channelID
	sfuRoom := h.manager.GetOrCreateRoom(roomKey)

	peer, exists := sfuRoom.GetPeer(peerID)
	if !exists {
		log.Printf("[SFU] Renegotiate: peer %s not found (may have reconnected), ignoring\n", peerID)
		WriteJSON(w, http.StatusOK, map[string]string{"message": "peer gone, ignored"})
		return
	}

	state := peer.PeerConnection.SignalingState()
	log.Printf("[SFU] Renegotiate for %s — signaling state: %s\n", peerID, state)

	if state != webrtc.SignalingStateHaveLocalOffer {
		log.Printf("[SFU] Renegotiate for %s skipped — wrong state: %s\n", peerID, state)
		WriteJSON(w, http.StatusOK, map[string]string{"message": "wrong state, ignored"})
		return
	}

	if err := peer.PeerConnection.SetRemoteDescription(webrtc.SessionDescription{
		Type: webrtc.SDPTypeAnswer,
		SDP:  body.SDP,
	}); err != nil {
		log.Printf("[SFU] SetRemoteDescription error for %s: %v | state: %s\n", peerID, err, state)
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	log.Printf("[SFU] Renegotiate OK for %s\n", peerID)
	WriteJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}
