package handler

import (
	"encoding/json"
	"net/http"
	"walkie-talkie-app/internal/middleware"
	"walkie-talkie-app/internal/service"

	"github.com/golang-jwt/jwt/v5"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

type AuthHandler struct {
	authService *service.AuthService
}

func NewAuthHandler(authService *service.AuthService) *AuthHandler {
	return &AuthHandler{authService: authService}
}

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username    string `json:"username"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid request"})
		return
	}
	if body.Username == "" || body.Password == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Username and password required"})
		return
	}
	user, err := h.authService.Register(r.Context(), body.Username, body.Password, body.DisplayName)
	if err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusCreated, map[string]string{
		"message":  "registered",
		"username": user.Username,
	})
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid request"})
		return
	}
	token, user, err := h.authService.Login(r.Context(), body.Username, body.Password)
	if err != nil {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusOK, map[string]interface{}{
		"token":        token,
		"user_id":      user.ID.Hex(),
		"username":     user.Username,
		"display_name": user.DisplayName,
		"invite_code":  user.InviteCode,
	})
}

// PUT /auth/profile
func (h *AuthHandler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(middleware.UserKey).(*jwt.MapClaims)
	if !ok {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	userIDStr, _ := (*claims)["user_id"].(string)
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid user id"})
		return
	}

	var body struct {
		DisplayName string `json:"display_name"`
		NewPassword string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request"})
		return
	}

	if err := h.authService.UpdateProfile(r.Context(), userID, body.DisplayName, body.NewPassword); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusOK, map[string]string{"message": "profile updated"})
}

// DELETE /auth/profile
func (h *AuthHandler) DeleteAccount(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(middleware.UserKey).(*jwt.MapClaims)
	if !ok {
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	userIDStr, _ := (*claims)["user_id"].(string)
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid user id"})
		return
	}

	var body struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Password == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "password required"})
		return
	}

	if err := h.authService.DeleteAccount(r.Context(), userID, body.Password); err != nil {
		WriteJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()})
		return
	}
	WriteJSON(w, http.StatusOK, map[string]string{"message": "account deleted"})
}

// ── Helpers ──────────────────────────────────────────────

func WriteJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	WriteJSON(w, status, map[string]string{"error": msg})
}
