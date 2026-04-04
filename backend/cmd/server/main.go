package main

import (
	"log"
	"net/http"
	"os"
	"strings"

	"walkie-talkie-app/internal/config"
	"walkie-talkie-app/internal/handler"
	"walkie-talkie-app/internal/middleware"
	"walkie-talkie-app/internal/repository"
	"walkie-talkie-app/internal/service"
	"walkie-talkie-app/internal/websocket"

	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("[WARN] No .env file found")
	}

	config.ConnectMongo(os.Getenv("MONGO_URI"), os.Getenv("MONGO_DB"))

	// Wire up
	roomRepo := repository.NewRoomRepository(config.DB)
	channelRepo := repository.NewChannelRepository(config.DB)
	roomService := service.NewRoomService(roomRepo, channelRepo)
	roomHandler := handler.NewRoomHandler(roomService)
	userRepo := repository.NewUserRepository(config.DB)
	authService := service.NewAuthService(userRepo)
	authHandler := handler.NewAuthHandler(authService)

	// Routes
	http.HandleFunc("/auth/register", authHandler.Register)
	http.HandleFunc("/auth/login", authHandler.Login)

	//Route have proctect
	http.HandleFunc("/profile", middleware.AuthMiddleware(authService, func(w http.ResponseWriter, r *http.Request) {
		claims := r.Context().Value(middleware.UserKey)
		handler.WriteJSON(w, http.StatusOK, claims)

	}))

	//Routes Room
	http.HandleFunc("/rooms", middleware.AuthMiddleware(authService, roomHandler.CreateRoom))
	http.HandleFunc("/rooms/", middleware.AuthMiddleware(authService, func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/channels") {
			roomHandler.CreateChannel(w, r)
		} else if strings.HasSuffix(r.URL.Path, "/members") {
			roomHandler.AddMember(w, r)
		}

	}))
	//WebSocket claim authService
	http.HandleFunc("/websocket", websocket.HandleWebsocket(authService, roomRepo, channelRepo))
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Println("[SERVER] Running on :" + port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
