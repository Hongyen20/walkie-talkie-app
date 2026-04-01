package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"walkie-talkie-app/internal/config"
	"walkie-talkie-app/internal/websocket"

	"github.com/joho/godotenv"
)

func main(){
	//Load .env
	if err := godotenv.Load(); err !=nil{
		log.Println("[WARN] No .env file found")
	}

	//Connect to MongoDB
	config.ConnectMongo(
		os.Getenv("MONGO_URI"),
		os.Getenv("MONGO_DB"),
	)

	//Routes
	http.HandleFunc("/websocket", websocket.HandleWebsocket)
	port := os.Getenv("PORT")
	if port ==""{
		port = "8080"
	}
	fmt.Println("Server running at :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}