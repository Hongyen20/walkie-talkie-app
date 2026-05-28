package room

import (
	"fmt"
	"log"
	"sync"

	"github.com/gorilla/websocket"
)

type Client struct {
	ID        string
	Conn      *websocket.Conn
	RoomID    string
	ChannelID string
}

type Room struct {
	Name    string
	Clients map[*websocket.Conn]*Client
	mutex   sync.Mutex
}

func NewRoom(name string) *Room {
	return &Room{
		Name:    name,
		Clients: make(map[*websocket.Conn]*Client),
	}
}

func (r *Room) AddClient(c *Client) {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	r.Clients[c.Conn] = c
	log.Printf("[ROOM %s] ADD %s\n", r.Name, c.ID)
}

func (r *Room) RemoveClient(c *Client) {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	delete(r.Clients, c.Conn)
	log.Printf("[ROOM %s] REMOVE %s\n", r.Name, c.ID)
}

func (r *Room) BroadcastToChannel(sender *Client, channelID string, msg []byte) {
	r.mutex.Lock()
	defer r.mutex.Unlock()

	var toRemove []*Client
	for _, client := range r.Clients {
		if client.ID == sender.ID {
			continue
		}
		if client.ChannelID != channelID {
			continue
		}
		err := client.Conn.WriteMessage(websocket.TextMessage, msg)
		if err != nil {
			log.Println("[ERROR] Write:", err)
			client.Conn.Close()
			toRemove = append(toRemove, client)
		}
	}
	for _, client := range toRemove {
		delete(r.Clients, client.Conn)
	}
}

func (r *Room) BroadcastToRoom(sender *Client, msg []byte) {
	r.mutex.Lock()
	defer r.mutex.Unlock()

	// deduplicate — mỗi username chỉ nhận 1 lần dù có nhiều connection
	sent := make(map[string]bool)
	var toRemove []*Client
	for _, client := range r.Clients {
		if client.ID == sender.ID {
			continue
		}
		if sent[client.ID] {
			continue
		}
		err := client.Conn.WriteMessage(websocket.TextMessage, msg)
		if err != nil {
			log.Println("[ERROR] BroadcastToRoom write:", err)
			client.Conn.Close()
			toRemove = append(toRemove, client)
			continue
		}
		sent[client.ID] = true
	}
	for _, client := range toRemove {
		delete(r.Clients, client.Conn)
	}
}

func (r *Room) SendTo(targetID string, msg []byte) error {
	r.mutex.Lock()
	defer r.mutex.Unlock()

	for _, client := range r.Clients {
		if client.ID == targetID {
			return client.Conn.WriteMessage(websocket.TextMessage, msg)
		}
	}
	return fmt.Errorf("Client %s not found", targetID)
}

func (r *Room) GetClientIDs() []string {
	r.mutex.Lock()
	defer r.mutex.Unlock()

	ids := make([]string, 0, len(r.Clients))
	for _, client := range r.Clients {
		ids = append(ids, client.ID)
	}
	return ids
}

// deduplicate — mỗi username chỉ xuất hiện 1 lần dù có nhiều WS connection
func (r *Room) GetClientIDsByChannel(channelID string) []string {
	r.mutex.Lock()
	defer r.mutex.Unlock()

	seen := make(map[string]bool)
	ids := make([]string, 0)
	for _, client := range r.Clients {
		if client.ChannelID == channelID && !seen[client.ID] {
			seen[client.ID] = true
			ids = append(ids, client.ID)
		}
	}
	return ids
}

type RoomManager struct {
	rooms map[string]*Room
	mutex sync.Mutex
}

func NewRoomManager() *RoomManager {
	return &RoomManager{
		rooms: make(map[string]*Room),
	}
}

func (m *RoomManager) GetOrCreate(roomID string) *Room {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	if r, ok := m.rooms[roomID]; ok {
		return r
	}
	r := NewRoom(roomID)
	m.rooms[roomID] = r
	log.Printf("[MANAGER] Created room %s\n", roomID)
	return r
}

func (m *RoomManager) CleanIfEmpty(roomID string) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	if r, ok := m.rooms[roomID]; ok {
		r.mutex.Lock()
		count := len(r.Clients)
		r.mutex.Unlock()
		if count == 0 {
			delete(m.rooms, roomID)
			log.Printf("[MANAGER] Removed empty room %s\n", roomID)
		}
	}
}

func (m *RoomManager) SendToUser(username string, msg []byte) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	log.Printf("[WS] SendToUser %s — rooms count: %d\n", username, len(m.rooms))
	for roomID, r := range m.rooms {
		r.mutex.Lock()
		log.Printf("[WS] Checking room %s — clients: %d\n", roomID, len(r.Clients))
		for _, client := range r.Clients {
			log.Printf("[WS] Client: %s\n", client.ID)
			if client.ID == username {
				log.Printf("[WS] Found and sending to %s\n", username)
				client.Conn.WriteMessage(websocket.TextMessage, msg)
			}
		}
		r.mutex.Unlock()
	}
}
