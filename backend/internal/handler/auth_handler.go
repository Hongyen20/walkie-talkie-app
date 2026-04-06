package handler

import (
	"encoding/json"
	"net/http"
	"regexp"
	"walkie-talkie-app/internal/service"
)

type AuthHandler struct {
	authService *service.AuthService
}

func NewAuthHandler(authService *service.AuthService) *AuthHandler {
	return &AuthHandler{authService: authService}
}

func isValidName(s string) bool {
	//DisplayName and Username don't use special characters.
	re := regexp.MustCompile(`^[a-zA-Z0-9_ ]+$`)
	return re.MatchString(s)
}

// POST /auth/register
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username    string `json:"username"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	existing, _ := h.authService.FindByUserName(r.Context(), body.Username)
	if existing != nil {
		WriteJSON(w, http.StatusConflict, map[string]string{"error": "Username already exists"})
		return
	}
	if body.Username == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Username is required"})
		return
	}
	if !isValidName(body.Username) {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Username must not contain special characters"})
		return
	}
	//var existing *model.User
	existing, _ = h.authService.FindByUserName(r.Context(), body.Username)
	if existing != nil {
		WriteJSON(w, http.StatusConflict, map[string]string{"error": "Username already exists"})
		return
	}

	if body.DisplayName == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Display name is required"})
		return
	}
	if !isValidName(body.DisplayName) {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Display name must not contain special characters"})
		return
	}

	if body.Password == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Password is required"})
		return
	}
	if len(body.Password) < 8 {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "Password must be at least 8 characters"})
		return
	}

	user, err := h.authService.Register(r.Context(), body.Username, body.Password, body.DisplayName)
	if err != nil {
		writeError(w, http.StatusConflict, err.Error())
		return
	}
	WriteJSON(w, http.StatusCreated, map[string]any{
		"message":     "Register successful",
		"user_id":     user.ID.Hex(),
		"invite_code": user.InviteCode,
	})
}

// POST /auth/login
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	token, user, err := h.authService.Login(r.Context(), body.Username, body.Password)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err.Error())
		return
	}
	WriteJSON(w, http.StatusOK, map[string]any{
		"token":        token,
		"user_id":      user.ID.Hex(),
		"username":     user.Username,
		"display_name": user.DisplayName,
		"invite_code":  user.InviteCode,
	})
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
