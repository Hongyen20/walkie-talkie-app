package websocket

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"walkie-talkie-backend/internal/room"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

var counterClient = 0

// Create a main room first
var mainRoom = room.NewRoom("main")

type Message struct {
	From    string `json: "from"`
	Message string `json: "message"`
}

func HandleWebsocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}

	//Create Client
	counterClient++
	id := fmt.Sprintf("user %d", counterClient)

	client := &room.Client{
		ID:   id,
		Conn: conn,
	}

	mainRoom.AddClient(client)

	log.Printf("[CONNECT] %s\n, id")

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
		log.Printf("[RECV] %s : %s\n", id, string(msg))

		//Encapsulate message
		m := Message{
			From:    id,
			Message: string(msg),
		}
		jsonMsg, _ := json.Marshal(m)

		mainRoom.Broadcast(client, jsonMsg)
	}
}
