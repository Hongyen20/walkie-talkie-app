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

	mux := http.NewServeMux()

	mux.HandleFunc("/auth/register", authHandler.Register)
	mux.HandleFunc("/auth/login", authHandler.Login)
	mux.HandleFunc("/profile", middleware.AuthMiddleware(authService, func(w http.ResponseWriter, r *http.Request) {
		claims := r.Context().Value(middleware.UserKey)
		handler.WriteJSON(w, http.StatusOK, claims)
	}))
	mux.HandleFunc("/rooms/", middleware.AuthMiddleware(authService, func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/channels") {
			roomHandler.CreateChannel(w, r)
		} else if strings.HasSuffix(r.URL.Path, "/members") {
			roomHandler.AddMember(w, r)
		}
	}))

	mux.HandleFunc("/websocket", websocket.HandleWebsocket(authService, roomRepo, channelRepo))
	//ADD GET /rooms
	mux.HandleFunc("/rooms", middleware.AuthMiddleware(authService, func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "GET" {
			roomHandler.GetRooms(w, r)
		} else if r.Method == "POST" {
			roomHandler.CreateRoom(w, r)
		}
	}))
	
	//Join room
	mux.HandleFunc("/rooms/join", middleware.AuthMiddleware(authService, roomHandler.JoinRoom))
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Wrap mux với CORS
	log.Println("[SERVER] Running on :" + port)
	log.Fatal(http.ListenAndServe(":"+port, corsMiddleware(mux)))

}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		// Handle preflight request
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}
