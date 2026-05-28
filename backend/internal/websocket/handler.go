package websocket

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
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

var mainRoom = room.NewRoom("main")
var manager = room.NewRoomManager()

var Manager = manager

func GetManager() *room.RoomManager {
	return manager
}

type Message struct {
	Type    string          `json:"type"`
	From    string          `json:"from"`
	To      string          `json:"to"`
	Message json.RawMessage `json:"message"`
}

func HandleWebsocket(authService *service.AuthService, roomRepo *repository.RoomRepository, channelRepo *repository.ChannelRepository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tokenStr := r.URL.Query().Get("token")
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

		roomIDStr := r.URL.Query().Get("room_id")
		channelIDStr := r.URL.Query().Get("channel_id")
		if roomIDStr == "" {
			http.Error(w, `{"error":"missing room_id"}`, http.StatusBadRequest)
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
		if !roomRepo.IsMember(r.Context(), roomID, userID) {
			http.Error(w, `{"error":"not a member of this room"}`, http.StatusForbidden)
			return
		}

		channelID, err := primitive.ObjectIDFromHex(channelIDStr)
		if err != nil {
			http.Error(w, `{"error":"Invalid Channel_id"}`, http.StatusBadRequest)
			return
		}
		ch, err := channelRepo.FindByID(r.Context(), channelID)
		if err != nil || ch.RoomID != roomID {
			http.Error(w, `{"error":"channel not found in room"}`, http.StatusForbidden)
			return
		}
		if ch.IsLocked {
			http.Error(w, `{"error":"channel is locked"}`, http.StatusForbidden)
			return
		}

		isOwner := roomRepo.IsOwner(r.Context(), roomID, userID)

		// Lấy query param broadcast để phân biệt broadcast WS với PTT WS
		isBroadcastOnly := r.URL.Query().Get("broadcast") == "1"

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Println("Upgrade error:", err)
			return
		}
		client := &room.Client{
			ID:        username,
			Conn:      conn,
			RoomID:    roomIDStr,
			ChannelID: channelIDStr,
		}

		wsRoom := manager.GetOrCreate(roomIDStr)
		wsRoom.AddClient(client)
		log.Printf("[CONNECT] %s -> room=%s channel=%s broadcast=%v\n", username, roomIDStr, channelIDStr, isBroadcastOnly)

		defer func() {
			wsRoom.RemoveClient(client)
			// Broadcast WS không gửi user-left — tránh làm online list sai
			if !isBroadcastOnly {
				leftMsg, _ := json.Marshal(map[string]string{
					"type": "user-left",
					"from": username,
				})
				wsRoom.BroadcastToChannel(client, channelIDStr, leftMsg)
			}
			conn.Close()
			manager.CleanIfEmpty(roomIDStr)
			log.Printf("[DISCONNECT] %s\n", username)
		}()

		// Broadcast WS chỉ cần nhận sfu-renegotiate, không gửi your-id hay online-list
		if !isBroadcastOnly {
			selfMsgStr, _ := json.Marshal(username)
			selfMsg := Message{
				Type:    "your-id",
				From:    "server",
				Message: selfMsgStr,
			}
			jsonSelf, _ := json.Marshal(selfMsg)
			wsRoom.SendTo(username, jsonSelf)
		}

		for {
			_, msg, err := conn.ReadMessage()
			if err != nil {
				log.Println("Read error:", err)
				break
			}

			var incoming Message
			if err := json.Unmarshal(msg, &incoming); err != nil {
				rawMsg, _ := json.Marshal(string(msg))
				incoming = Message{
					Type:    "chat",
					From:    username,
					Message: rawMsg,
				}
			} else {
				incoming.From = username
			}

			log.Printf("[RECV] %s | type=%s | to=%s\n", username, incoming.Type, incoming.To)

			switch incoming.Type {
			case "join":
				// Broadcast WS không join online list
				if isBroadcastOnly {
					continue
				}
				// Deduplicate online list
				rawList := wsRoom.GetClientIDsByChannel(channelIDStr)
				listStr := strings.Join(rawList, ",")
				listJSON, _ := json.Marshal(listStr)
				onlineList := Message{
					Type:    "online-list",
					From:    "server",
					Message: listJSON,
				}
				jsonList, _ := json.Marshal(onlineList)
				wsRoom.SendTo(username, jsonList)

				// FIX: chỉ broadcast user-joined nếu đây là connection đầu tiên của user trong channel
				// (tránh broadcast 2 lần khi owner vào channel đồng thời có broadcast WS)
				connectionCount := 0
				for _, id := range wsRoom.GetClientIDsByChannel(channelIDStr) {
					if id == username {
						connectionCount++
					}
				}
				// GetClientIDsByChannel đã deduplicate nên count luôn = 1 nếu user có mặt
				// Broadcast user-joined bình thường
				notifyMsg, _ := json.Marshal(username + " joined channel")
				notify := Message{
					Type:    "user-joined",
					From:    username,
					Message: notifyMsg,
				}
				jsonMsg, _ := json.Marshal(notify)
				wsRoom.BroadcastToChannel(client, channelIDStr, jsonMsg)

			case "offer", "answer", "ice-candidate":
				if incoming.To == "" {
					log.Println("[WARN] Missing field 'to'")
					continue
				}
				jsonMsg, _ := json.Marshal(incoming)
				if err := wsRoom.SendTo(incoming.To, jsonMsg); err != nil {
					log.Printf("[WARN] SendTo %s fail: %v\n", incoming.To, err)
				}

			case "chat":
				jsonMsg, _ := json.Marshal(incoming)
				wsRoom.BroadcastToChannel(client, channelIDStr, jsonMsg)

			case "ptt-start", "ptt-stop":
				jsonMsg, _ := json.Marshal(incoming)
				wsRoom.BroadcastToChannel(client, channelIDStr, jsonMsg)

			case "broadcast-start":
				if !isOwner {
					log.Printf("[WARN] %s is not owner, broadcast rejected\n", username)
					continue
				}
				jsonMsg, _ := json.Marshal(incoming)
				wsRoom.BroadcastToRoom(client, jsonMsg)
				log.Printf("[BROADCAST] %s started broadcasting\n", username)

			case "broadcast-stop":
				if !isOwner {
					continue
				}
				jsonMsg, _ := json.Marshal(incoming)
				wsRoom.BroadcastToRoom(client, jsonMsg)
				log.Printf("[BROADCAST] %s stopped broadcasting\n", username)

			default:
				log.Printf("[WARN] Unknown type: %s\n", incoming.Type)
			}
		}
	}
}
