package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func handleWebsockt(w http.ResponseWriter, r *http.Request) {
	fmt.Sprintln("Client connecting...")
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}
	defer conn.Close()

	fmt.Sprintln("Client connected!")
	for {
		//Đọc message client gửi
		messageType, msg, err := conn.ReadMessage()
		if err != nil {
			log.Println("Read error:", err)
			break
		}
		fmt.Println("Received: ", string(msg))

		//
		err = conn.WriteMessage(messageType, msg)
		if err != nil {
			log.Println("write error: ", err)
			break
		}
	}
}

func main() {
	http.HandleFunc("/websocket", handleWebsockt)

	fmt.Println("Server running at : 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
