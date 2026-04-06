package service

import (
	"context"
	"errors"
	"math/rand"
	"os"
	"time"
	"walkie-talkie-app/internal/model"
	"walkie-talkie-app/internal/repository"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

type AuthService struct {
	userRepo *repository.UserRepository
}

func NewAuthService(userRepo *repository.UserRepository) *AuthService {
	return &AuthService{userRepo: userRepo}
}

// Register
func (s *AuthService) Register(ctx context.Context, username, password, displayName string) (*model.User, error) {
	//Hash password
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}

	user := &model.User{
		Username:    username,
		Password:    string(hash),
		DisplayName: displayName,
		InviteCode:  generateInviteCode(),
	}

	if err := s.userRepo.Create(ctx, user); err != nil {
		return nil, errors.New("Username already exists")
	}
	return user, nil
}


// Login
func (s *AuthService) Login(ctx context.Context, username, password string) (string, *model.User, error) {
	user, err := s.userRepo.FindByUserName(ctx, username)
	if err != nil {
		return "", nil, errors.New("Username not found")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(password)); err != nil {
		return "", nil, errors.New("Incorrect password")
	}

	token, err := generateJWT(user)
	if err != nil {
		return "", nil, err
	}
	return token, user, nil
}

// Verify JWT
func (s *AuthService) VerifyToken(tokenStr string) (*jwt.MapClaims, error) {
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		return []byte(os.Getenv("JWT_SECRET")), nil
	})
	if err != nil || !token.Valid {
		return nil, errors.New("Invalid Token")
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return nil, errors.New("Invalid Claims")
	}
	return &claims, nil
}

// Helper
func generateJWT(user *model.User) (string, error) {
	claims := jwt.MapClaims{
		"user_id":  user.ID.Hex(),
		"username": user.Username,
		"exp":      time.Now().Add(7 * 24 * time.Hour).Unix(), // hết hạn 7 ngày
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(os.Getenv("JWT_SECRET")))
}

func generateInviteCode() string {
	const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	code := make([]byte, 8)
	for i := range code {
		code[i] = chars[r.Intn(len(chars))]
	}
	return string(code)
}

func (s *AuthService) FindByUserName(ctx context.Context, username string) (*model.User, error) {
	return s.userRepo.FindByUserName(ctx, username)
}
