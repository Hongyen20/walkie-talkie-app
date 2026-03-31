package main

import (
	"fmt"
	"log"
	"net/http"
	"walkie-talkie-backend/internal/websocket"
)

func main(){
	http.HandleFunc("/websocket", websocket.HandleWebsocket)
	fmt.Println("Server running at :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}