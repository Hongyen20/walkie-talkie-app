package websocket

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync/atomic"
	"walkie-talkie-app/internal/room"

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

func HandleWebsocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}

	//Create Client, avoid 2 user have duplicate ID
	id := fmt.Sprintf("user %d", atomic.AddInt64(&counterClient, 1))

	client := &room.Client{
		ID:   id,
		Conn: conn,
	}

	mainRoom.AddClient(client)

	log.Printf("[CONNECT] %s\n", id)

	defer func() {
		mainRoom.RemoveClient(client)
		conn.Close()
		log.Printf("[DISCONNECT] %s\n", id)
	}()

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
				From:    id,
				Message: string(msg),
			}
		} else {
			incoming.From = id
		}

		log.Printf("[RECV] %s | type=%s | to=%s | message=%s\n", id, incoming.Type, incoming.To, incoming.Message)

		switch incoming.Type {
		case "join":
			//Resend ID for this client after join room
			selfMsg := Message{
				Type:    "your-id",
				From:    "server",
				Message: id,
			}
			jsonSelf, _ := json.Marshal(selfMsg)
			mainRoom.SendTo(id, jsonSelf)

			//Notify for users know when someone join
			notify := Message{
				Type:    "user-joined",
				From:    id,
				Message: id + "entered the room",
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
