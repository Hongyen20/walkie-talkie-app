package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"walkie-talkie-app/internal/middleware"
	"walkie-talkie-app/internal/service"

	"github.com/golang-jwt/jwt/v5"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

type RoomHandler struct {
	roomService *service.RoomService
}

func NewRoomHandler(roomService *service.RoomService) *RoomHandler {
	return &RoomHandler{roomService: roomService}
}

// Helper get userID from JWT context
func getUserID(r *http.Request) (primitive.ObjectID, error) {
	claims, ok := r.Context().Value(middleware.UserKey).(*jwt.MapClaims)
	if !ok {
		return primitive.NilObjectID, errors.New("Invalid claims")
	}
	userIDStr, ok := (*claims)["user_id"].(string)
	if !ok {
		return primitive.NilObjectID, errors.New("Invalid user_id")
	}
	return primitive.ObjectIDFromHex(userIDStr)

}

// POST /rooms
func (h *RoomHandler) CreateRoom(w http.ResponseWriter, r *http.Request) {
	ownerID, err := getUserID(r)
	if err != nil {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "Unnauthozied"})
		return
	}
	var body struct {
		Name string `json:"name"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	if body.Name == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "name required"})
		return
	}
	room, err := h.roomService.CreateRoom(r.Context(), ownerID, body.Name)
	if err != nil {
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusCreated, room)
}

// POST /rooms/{roomID}/channels
func (h *RoomHandler) CreateChannel(w http.ResponseWriter, r *http.Request) {
	ownerID, err := getUserID(r)
	if err != nil {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	// URL : /rooms/
	parts := strings.Split(r.URL.Path, "/")
	// parts = ["", "rooms", "69cfcc...", "channels"]
	if len(parts) < 4 {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid url"})
		return
	}
	roomID, err := primitive.ObjectIDFromHex(parts[2])
	if err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid room id"})
		return
	}
	var body struct {
		Name string `json:"name"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	if body.Name == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Name required"})
		return
	}
	ch, err := h.roomService.CreateChannel(r.Context(), roomID, ownerID, body.Name)
	if err != nil {
		WriteJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusCreated, ch)
}

// POST /rooms/{roomId}/members
func (h *RoomHandler) AddMember(w http.ResponseWriter, r *http.Request) {
	ownerID, err := getUserID(r)
	if err != nil {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthozied"})
		return
	}
	roomID, _ := primitive.ObjectIDFromHex(strings.Split(r.URL.Path, "/")[2]) //Get element 3rd
	var body struct {
		UserID string `json:"user_id"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	userID, err := primitive.ObjectIDFromHex(body.UserID)
	if err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid user_id"})
		return
	}
	if err := h.roomService.AddMember(r.Context(), roomID, ownerID, userID); err != nil {
		WriteJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()}) //ban
		return
	}
	WriteJSON(w, http.StatusOK, map[string]string{"message": "member added"})
}

// GET /rooms
func (h *RoomHandler) GetRooms(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	rooms, err := h.roomService.GetRoomsByUser(r.Context(), userID)
	if err != nil {
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusOK, rooms)
}

// POST /rooms/join
func (h *RoomHandler) JoinRoom(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	var body struct {
		InviteCode string `json:"invite_code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.InviteCode == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invite_code is required"})
		return
	}
	room, err := h.roomService.JoinByInviteCode(r.Context(), userID, body.InviteCode)
	if err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusOK, room)
}

// GET /rooms/:id/channels
func (h *RoomHandler) GetChannels(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unathorized"})
		return
	}
	parts := strings.Split(r.URL.Path, "/")
	// /rooms/:id/channels → parts = ["", "rooms", ":id", "channels"]
	if len(parts) < 4 {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid url"})
		return
	}
	roomID, err := primitive.ObjectIDFromHex(parts[2])
	if err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid room id"})
		return
	}

	//Check user in a room
	if !h.roomService.IsMember(r.Context(), roomID, userID) {
		WriteJSON(w, http.StatusForbidden, map[string]string{"error": "Not a member"})
		return
	}

	channels, err := h.roomService.GetChannels(r.Context(), roomID)
	if err != nil {
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusOK, channels)
}

// DELETE /rooms/:id
func (h *RoomHandler) DeleteRoom(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorzied"})
		return
	}
	parts := strings.Split(r.URL.Path, "/")
	roomID, err := primitive.ObjectIDFromHex(parts[2])
	if err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid room id"})
		return
	}
	if err := h.roomService.DeleteRoom(r.Context(), roomID, userID); err != nil {
		WriteJSON(w, http.StatusForbidden, map[string]string{"error": "error"})
		return
	}
	WriteJSON(w, http.StatusOK, map[string]string{"message": "Room Deleted"})
}

// Delete /rooms/:id/channels/:channelID
func (h *RoomHandler) DeleteChannel(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserID(r)
	if err != nil {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthozied"})
		return
	}
	parts := strings.Split(r.URL.Path, "/")
	// /rooms/:roomId/channels/:channelId
	// parts = ["", "rooms", ":roomId", "channels", ":channelId"]
	if len(parts) < 5 {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid URL"})
		return
	}
	roomID, err := primitive.ObjectIDFromHex(parts[2])
	if err != nil  {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error":"Invalid room id"})
		return
	}
	channelID, err := primitive.ObjectIDFromHex(parts[4])
	if err != nil{
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error":"Inavlid channel id"})
		return
	}

	if err := h.roomService.DeleteChannel(r.Context(), roomID, channelID, userID); err != nil{
		WriteJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusOK, map[string]string{"message": "channel deleted"})

}
// DELETE /rooms/:id/leave
func (h *RoomHandler) LeaveRoom(w http.ResponseWriter, r *http.Request){
	userID, err := getUserID(r)
	if err != nil{
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error":"unauthozied"})
		return
	}
	parts := strings.Split(r.URL.Path,"/")
	roomID, err := primitive.ObjectIDFromHex(parts[2])
	if err != nil{
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalio room id"})
		return
	}
	if err := h.roomService.LeaveRoom(r.Context(), roomID, userID); err !=nil{
		WriteJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusOK, map[string]string{"message": "left room"})
}

