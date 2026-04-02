package websocket

import (
	"encoding/json"
	"log"
	"net/http"

	"walkie-talkie-app/internal/room"
	"walkie-talkie-app/internal/service"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

var counterClient int64

// Create a main room first
var mainRoom = room.NewRoom("main")

type Message struct {
	Type    string `json:"type"` //chat - offer - answer - candidate
	From    string `json:"from"`
	To      string `json:"to"`
	Message string `json:"message"`
}

func HandleWebsocket(authService *service.AuthService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request){
		//Get token fron query param: ws//localhost:8080/websocket?token=xxx
		tokenStr := r.URL.Query().Get("token")
		if tokenStr == ""{
			http.Error(w, "missing token", http.StatusUnauthorized)
			return 
		}
		
		claims, err := authService.VerifyToken(tokenStr)
		if err != nil{
			http.Error(w, "invalid token", http.StatusUnauthorized)
			return 
		}

		//Get username from token
		username := (*claims)["username"].(string)

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
		log.Println("Upgrade error:", err)
		return
	}
	client := &room.Client{
		ID:   username, //use username instead of user1, user2
		Conn: conn,
	}
	mainRoom.AddClient(client)
	log.Printf("[CONNECT] %s\n", username)
	defer func() {
		mainRoom.RemoveClient(client)
		conn.Close()
		log.Printf("[DISCONNECT] %s\n", username)
	}()
	
	//Send ID for client
	selfMsg := Message{
		Type: "your-id",
		From: "server",
		Message: username,
	}
	jsonSelf, _ := json.Marshal(selfMsg)
	mainRoom.SendTo(username, jsonSelf)
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

		log.Printf("[RECV] %s | type=%s | to=%s | message=%s\n", username, incoming.Type, incoming.To, incoming.Message)

		switch incoming.Type {
		case "join":
			//Resend ID for this client after join room
			selfMsg := Message{
				Type:    "your-id",
				From:    "server",
				Message: username,
			}
			jsonSelf, _ := json.Marshal(selfMsg)
			mainRoom.SendTo(username, jsonSelf)

			//Notify for users know when someone join
			notify := Message{
				Type:    "user-joined",
				From:    username,
				Message: username + "entered the room",
			}
			jsonMsg, _ := json.Marshal(notify)
			mainRoom.Broadcast(client, jsonMsg) //send to everyone (-client sending)

		case "offer", "answer", "ice-candidate":
			// Forward to correct receiver
			if incoming.To == "" {
				log.Println("[WARN] Mising field 'to'")
				continue
			}
			jsonMsg, _ := json.Marshal(incoming)
			if err := mainRoom.SendTo(incoming.To, jsonMsg); err != nil {
				log.Printf("[WARN] SendTo %s fail: %v\n", incoming.To, err)
			}
		case "chat":
			jsonMsg, _ := json.Marshal(incoming)
			mainRoom.Broadcast(client, jsonMsg)

		default:
			log.Printf("[WARN]Unknown type: %s\n", incoming.Type)
		}
	}


	}
}
