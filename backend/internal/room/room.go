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
	RoomID string
	ChannelID string
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

//Broadcast just 1 channel
func (r *Room) BroadcastToChannel(sender *Client, channelID string, msg []byte){
	r.mutex.Lock()
	defer r.mutex.Unlock()

	var toRemove []*Client
	for _, client := range r.Clients{
		if client.ID == sender.ID{
			continue //just send in channel
		}


		err := client.Conn.WriteMessage(websocket.TextMessage, msg)
		if err != nil{
			log.Println("[ERROR] Write:" , err)
			client.Conn.Close()

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


//RoomManager
type RoomManager struct{
	rooms map[string]*Room //Key: roomID
	mutex sync.Mutex
}

func NewRoomManager() *RoomManager{
	return &RoomManager{
		rooms: make(map[string]*Room),
	}
}

//Get room if u have ID, create a new one if u don't have
func (m *RoomManager) GetOrCreate(roomID string) *Room{
	m.mutex.Lock()
	defer m.mutex.Unlock()

	if r, ok := m.rooms[roomID]; ok{
		return r
	}
	r := NewRoom(roomID)
	m.rooms[roomID] = r
	log.Printf("[MANAGER] Created room %s/n", roomID)
	return r
}

//Delete room if noone in room
func (m *RoomManager) CleanIfEmpty(roomID string){
	m.mutex.Lock()
	defer m.mutex.Unlock()
	if r, ok := m.rooms[roomID]; ok{
		r.mutex.Lock()
		count := len(r.Clients)
		r.mutex.Unlock()
		if count == 0{
			delete(m.rooms, roomID)
			log.Printf("[MANAGER] Removed empty room &s\n", roomID)
		}
	}
}