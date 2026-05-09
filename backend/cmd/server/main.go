package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"

	"walkie-talkie-app/internal/config"
	"walkie-talkie-app/internal/handler"
	"walkie-talkie-app/internal/middleware"
	"walkie-talkie-app/internal/repository"
	"walkie-talkie-app/internal/service"
	"walkie-talkie-app/internal/sfu"
	"walkie-talkie-app/internal/websocket"

	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("[WARN] No .env file found")
	}

	config.ConnectMongo(os.Getenv("MONGO_URI"), os.Getenv("MONGO_DB"))

	// Wire up
	userRepo := repository.NewUserRepository(config.DB)
	roomRepo := repository.NewRoomRepository(config.DB)
	channelRepo := repository.NewChannelRepository(config.DB)

	authService := service.NewAuthService(userRepo)
	roomService := service.NewRoomService(roomRepo, channelRepo, config.DB)

	authHandler := handler.NewAuthHandler(authService)
	roomHandler := handler.NewRoomHandler(roomService)

	// WebSocket manager — use for notify renegotiation
	wsManager := websocket.GetManager()

	// notifyFunc with log debug
	notifyFunc := func(username string, msg map[string]interface{}) {
		data, _ := json.Marshal(msg)
		log.Printf("[NOTIFY] Sending to %s: %s\n", username, string(data))
		wsManager.SendToUser(username, data)
	}

	// SFU
	sfuManager := sfu.NewManager()
	sfuHandler := handler.NewSFUHandler(sfuManager, notifyFunc)

	mux := http.NewServeMux()

	// Auth routes
	mux.HandleFunc("/auth/register", authHandler.Register)
	mux.HandleFunc("/auth/login", authHandler.Login)
	mux.HandleFunc("/auth/profile", middleware.AuthMiddleware(authService, func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPut {
			authHandler.UpdateProfile(w, r)
		} else if r.Method == http.MethodDelete {
			authHandler.DeleteAccount(w, r)
		} else {
			handler.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		}
	}))

	mux.HandleFunc("/profile", middleware.AuthMiddleware(authService, func(w http.ResponseWriter, r *http.Request) {
		claims := r.Context().Value(middleware.UserKey)
		handler.WriteJSON(w, http.StatusOK, claims)
	}))

	// WebSocket
	mux.HandleFunc("/websocket", websocket.HandleWebsocket(authService, roomRepo, channelRepo))

	// Room routes
	mux.HandleFunc("/rooms", middleware.AuthMiddleware(authService, func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "GET" {
			roomHandler.GetRooms(w, r)
		} else if r.Method == "POST" {
			roomHandler.CreateRoom(w, r)
		}
	}))

	mux.HandleFunc("/rooms/join", middleware.AuthMiddleware(authService, roomHandler.JoinRoom))

	mux.HandleFunc("/rooms/", middleware.AuthMiddleware(authService, func(w http.ResponseWriter, r *http.Request) {
		parts := strings.Split(strings.TrimSuffix(r.URL.Path, "/"), "/")

		if strings.HasSuffix(r.URL.Path, "/channels") {
			if r.Method == "GET" {
				roomHandler.GetChannels(w, r)
			} else if r.Method == "POST" {
				roomHandler.CreateChannel(w, r)
			}
		} else if strings.HasSuffix(r.URL.Path, "/leave") {
			if r.Method == "DELETE" {
				roomHandler.LeaveRoom(w, r)
			}
		} else if len(parts) == 6 && parts[3] == "channels" && parts[5] == "members" {
			if r.Method == "POST" {
				roomHandler.AddChannelMember(w, r)
			}
		} else if len(parts) == 7 && parts[3] == "channels" && parts[5] == "members" {
			if r.Method == "DELETE" {
				roomHandler.RemoveChannelMember(w, r)
			}
		} else if strings.HasSuffix(r.URL.Path, "/members") {
			if r.Method == "GET" {
				roomHandler.GetMembers(w, r)
			} else if r.Method == "POST" {
				roomHandler.AddMember(w, r)
			}
		} else if len(parts) == 5 && parts[3] == "channels" {
			if r.Method == "DELETE" {
				roomHandler.DeleteChannel(w, r)
			}
		} else if len(parts) == 5 && parts[3] == "members" {
			if r.Method == "DELETE" {
				roomHandler.KickMember(w, r)
			}
		} else if len(parts) == 3 {
			if r.Method == "DELETE" {
				roomHandler.DeleteRoom(w, r)
			}
		}
	}))

	// SFU routes
	mux.HandleFunc("/sfu/offer", middleware.AuthMiddleware(authService, sfuHandler.HandleOffer))
	mux.HandleFunc("/sfu/ice", middleware.AuthMiddleware(authService, sfuHandler.HandleICE))
	mux.HandleFunc("/sfu/leave", middleware.AuthMiddleware(authService, sfuHandler.HandleLeave))
	mux.HandleFunc("/sfu/renegotiate", middleware.AuthMiddleware(authService, sfuHandler.HandleRenegotiate))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Println("[SERVER] Running on :" + port)
	log.Fatal(http.ListenAndServe(":"+port, corsMiddleware(mux)))
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}
