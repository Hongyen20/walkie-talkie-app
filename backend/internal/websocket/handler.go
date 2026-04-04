package websocket

import (
	"encoding/json"
	"log"
	"net/http"
	"walkie-talkie-app/internal/repository"
	"walkie-talkie-app/internal/room"
	"walkie-talkie-app/internal/service"

	"github.com/gorilla/websocket"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

// var counterClient int64

// Create a main room first
var mainRoom = room.NewRoom("main")
var manager = room.NewRoomManager()

type Message struct {
	Type    string `json:"type"` //chat - offer - answer - candidate
	From    string `json:"from"`
	To      string `json:"to"`
	Message string `json:"message"`
}

func HandleWebsocket(authService *service.AuthService, roomRepo *repository.RoomRepository, channelRepo *repository.ChannelRepository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {

		//Verify JWT from quey param
		//Get token fron query param: ws//localhost:8080/websocket?token=xxx
		tokenStr := r.URL.Query().Get("token")
		//1. Verify JWT
		if tokenStr == "" {
			http.Error(w, `{"error":"missing token"}`, http.StatusUnauthorized)
			return
		}

		claims, err := authService.VerifyToken(tokenStr)
		if err != nil {
			http.Error(w, `"error":"invalid token"`, http.StatusUnauthorized)
			return
		}
		username := (*claims)["username"].(string)
		userIDStr := (*claims)["user_id"].(string)
		userID, _ := primitive.ObjectIDFromHex(userIDStr)
		
		//Get room_id and channel_id from query
		roomIDStr := r.URL.Query().Get("room_id")
		channelIDStr := r.URL.Query().Get("channel_id")
		if roomIDStr == "" {
			http.Error(w, `{"error":"missing room_id "}`, http.StatusBadRequest)
			return
		}
		if channelIDStr == "" {
			http.Error(w, `{"error":"missing channel_id"}`, http.StatusBadRequest)
			return
		}
		roomID, err := primitive.ObjectIDFromHex(roomIDStr)
		if err != nil {
			http.Error(w, `{"error":"Invalid room_id"}`, http.StatusBadRequest)
			return
		}
		if !roomRepo.IsMember(r.Context(), roomID, userID){
			http.Error(w, `"error":"not a member of this room"`, http.StatusForbidden)
			return
		}

		//Check channel belongs to room ??
		channelID, err := primitive.ObjectIDFromHex(channelIDStr)
		if err != nil {
			http.Error(w, `{"error":"Invalid Channel_id"}`, http.StatusBadRequest)
			return
		}
		ch, err := channelRepo.FindByID(r.Context(), channelID)
		if err != nil || ch.RoomID != roomID {
			http.Error(w, `{"error":"chaanel not found in room"}`, http.StatusForbidden)
			return
		}
		if ch.IsLocked {
			http.Error(w, `{"error","channel is locked"}`, http.StatusForbidden)
			return
		}

		//Upgrade to WebSocket
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Println("Upgrade error:", err)
			return
		}
		client := &room.Client{
			ID:        username, //use username instead of user1, user2
			Conn:      conn,
			RoomID:    roomIDStr,
			ChannelID: channelIDStr,
		}

		wsRoom := manager.GetOrCreate(roomIDStr)
		wsRoom.AddClient(client)
		log.Printf("[CONNECT] %s -> room = %s channel = %s \n", username, roomID, channelIDStr)

		defer func() {
			wsRoom.RemoveClient(client)
			conn.Close()
			manager.CleanIfEmpty(roomIDStr)
			log.Printf("[DISCONNECT] %s\n", username)
		}()

		//Send ID for client
		selfMsg := Message{
			Type:    "your-id",
			From:    "server",
			Message: username,
		}
		jsonSelf, _ := json.Marshal(selfMsg)
		wsRoom.SendTo(username, jsonSelf)

		//Message Loop
		for {
			_, msg, err := conn.ReadMessage()
			if err != nil {
				log.Println("Read error:", err)
				break
			}

			var incoming Message
			if err := json.Unmarshal(msg, &incoming); err != nil {
				incoming = Message{
					Type:    "chat",
					From:    username,
					Message: string(msg),
				}
			} else {
				incoming.From = username
			}

			log.Printf("[RECV] %s | type = %s | to = %s | message = %s\n", username, incoming.Type, incoming.To, incoming.Message)

			switch incoming.Type {
			case "join":
				//Notify for users know when someone join
				notify := Message{
					Type:    "user-joined",
					From:    username,
					Message: username + "joined channel",
				}
				jsonMsg, _ := json.Marshal(notify)
				wsRoom.BroadcastToChannel(client, channelIDStr, jsonMsg)
			case "offer", "answer", "ice-candidate":
				// Forward to correct receiver
				if incoming.To == "" {
					log.Println("[WARN] Mising field 'to'")
					continue
				}
				jsonMsg, _ := json.Marshal(incoming)
				if err := wsRoom.SendTo(incoming.To, jsonMsg); err != nil {
					log.Printf("[WARN] SendTo %s fail: %v\n", incoming.To, err)
				}
			case "chat":
				jsonMsg, _ := json.Marshal(incoming)
				wsRoom.BroadcastToChannel(client, channelIDStr, jsonMsg)

			default:
				log.Printf("[WARN]Unknown type: %s\n", incoming.Type)
			}
		}

	}
}
