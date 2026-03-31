package room

import (

	"log"
	"sync"

	"github.com/gorilla/websocket"
)
type Client struct{
	ID string 
	Conn *websocket.Conn
}

type Room struct{
	Name string
	Clients map[*websocket.Conn]*Client
	mutex	sync.Mutex
}

func NewRoom(name string) *Room{
	return &Room{
		Name: name,
		Clients: make(map[*websocket.Conn]*Client),
	}
}

func (r *Room) AddClient(c *Client){
	r.mutex.Lock()
	defer r.mutex.Unlock()
	r.Clients[c.Conn] = c
	log.Printf("[ROOM %s] ADD %\n", r.Name, c.ID)
}

func (r *Room) RemoveClient(c *Client){
	r.mutex.Lock()
	defer r.mutex.Unlock()

	delete(r.Clients, c.Conn)
	log.Printf("[ROOM %s] REMOVE %s\n", r.Name, c.ID)
}

func (r *Room) Broadcast(sender *Client, msg []byte){
	r.mutex.Lock()
	defer r.mutex.Unlock()

	for _, client := range r.Clients{
		err := client.Conn.WriteMessage(websocket.TextMessage, msg)
		if err != nil{
			log.Println("[ERROR] Write:" , err)
			client.Conn.Close()
			delete(r.Clients, client.Conn)
			continue
		}
	}
}