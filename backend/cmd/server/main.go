package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"

	
)

var ugrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}
//MODEL
type Client struct{
	ID string
	Conn *websocket.Conn
}

type Message struct{
	From string `json:"from"`
	Message string `json:"message"`
}
//Global variables
var(
	clients = make(map[*websocket.Conn]*Client)
	mutex sync.Mutex
	counterClient = 0
)

//HANDLER
func handleWebsocket(w http.ResponseWriter, r *http.Request){
	conn, err := ugrader.Upgrade(w, r, nil)
	if err != nil{
		log.Println("[ERROR Update: ", err)
		return
	}
	client :=registerClient(conn)
	defer unregisterClient(conn, client.ID)
	readLoop(client)
}

//CLIENT
func registerClient(conn *websocket.Conn) *Client{
	mutex.Lock()
	defer mutex.Unlock()

	counterClient++
	id := fmt.Sprintf("user-%d", counterClient)

	client := &Client{
		ID : id,
		Conn: conn,
	}
	
	clients[conn] = client
	
	log.Printf("[CONNECT] %s\n", id)
	return client
}

func unregisterClient(conn *websocket.Conn, id string){
	mutex.Lock()
	defer mutex.Unlock()

	delete(clients, conn)
	conn.Close()

	log.Printf("[DISCONNECTED] %s\n", id)
}

//
func readLoop(client *Client){
	for {
		_, msg, err := client.Conn.ReadMessage()
		if err != nil{
			log.Println("[ERROR] Read:", err)
			return
		}
		log.Println("RECV %s: %s\n", client.ID, string(msg))

		broadcast(client, msg)
	}
}

func broadcast(sender *Client, msg []byte){
	message := Message{
		From: sender.ID,
		Message: string(msg),
	}
	jsonMsg, _ := json.Marshal(message)

	mutex.Lock()
	defer mutex.Unlock()
	for _, client := range clients{
		err := client.Conn.WriteMessage(websocket.TextMessage, jsonMsg)
		if err != nil{
			log.Println("[ERROR] Write: ", err)
			client.Conn.Close()
			delete(clients, client.Conn)
			continue
		}
		log.Printf("[SEND] to %s\n", client.ID)
	}
}


//MAIN
func main(){
	http.HandleFunc("/websocket", handleWebsocket)
	fmt.Sprintln("Server running at port :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}