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
	if !ok{
		return primitive.NilObjectID, errors.New("Invalid claims")
	}
	userIDStr, ok := (*claims)["user_id"].(string)
	if !ok{
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
	if len(parts) <4 {
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
	if body.Name ==""{
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


//GET /rooms
func (h *RoomHandler) GetRooms(w http.ResponseWriter, r *http.Request){
	ownerID, err := getUserID(r)
	if err != nil{
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error":"unauthorized"})
		return
	}
	rooms, err := h.roomService.GetRoomsByOwner(r.Context(), ownerID)
	if err != nil {
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusOK, rooms)
}

