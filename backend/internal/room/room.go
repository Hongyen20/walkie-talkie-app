package room

import (
	"fmt"
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
	log.Printf("[ROOM %s] ADD %s\n", r.Name, c.ID)
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

	var toRemove []*Client
	for _, client := range r.Clients{
		if client.ID == sender.ID{
			continue //not send to this client
		}


		err := client.Conn.WriteMessage(websocket.TextMessage, msg)
		if err != nil{
			log.Println("[ERROR] Write:" , err)
			toRemove = append(toRemove, client)
			continue
		}
	}
	for  _, client := range toRemove{
		delete(r.Clients, client.Conn)
	}
}

func (r *Room) SendTo(targetID string, msg []byte) error{
	r.mutex.Lock()
	defer r.mutex.Unlock()

	for _, client := range r.Clients{
		if client.ID == targetID{
			return client.Conn.WriteMessage(websocket.TextMessage, msg)
		}
	}
	return fmt.Errorf("Client %s not found", targetID)
}

//Get list of IDs clients (notify when someone join)
func (r *Room) GetClientIDs() []string{
	r.mutex.Lock()
	defer r.mutex.Unlock()

	ids := make([]string, 0, len(r.Clients))
	for _,client:= range r.Clients{
		ids = append(ids, client.ID)
	}
	return ids
}