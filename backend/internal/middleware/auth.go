package middleware

import (
	"context"
	"net/http"
	"walkie-talkie-app/internal/service"
	"strings"
)

type contextKey string
const UserKey contextKey = "user_claims"

func AuthMiddleware(authService *service.AuthService, next http.HandlerFunc) http.HandlerFunc{
	return func(w http.ResponseWriter, r *http.Request) {
		//Get the token from the header: "Authorization: Bearer <token>"
	authHeader := r.Header.Get("Authorization")
	if authHeader == ""{
		http.Error(w, `{"error":"missing token"}`, http.StatusUnauthorized)
		return
	}
	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || parts[0] != "Bearer"{
		http.Error(w, `{"error":"invalid token format"}`, http.StatusUnauthorized)
		return 
	}
	claims, err := authService.VerifyToken(parts[1])
	if err != nil{
		http.Error(w, `{"error":"invalid token"}`, http.StatusUnauthorized)
		return
	}

	//Attach claims to the context for the handler to use.
	ctx := context.WithValue(r.Context(), UserKey, claims)
	next(w, r.WithContext(ctx))
	}
}
