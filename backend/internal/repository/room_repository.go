package repository

import (
	"context"
	"time"
	"walkie-talkie-app/internal/model"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type RoomRepository struct {
	rooms   *mongo.Collection
	members *mongo.Collection
}

func NewRoomRepository(db *mongo.Database) *RoomRepository {
	members := db.Collection("room_members")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	members.Indexes().CreateMany(ctx, []mongo.IndexModel{
		{Keys: bson.D{{Key: "room_id", Value: 1}}},
		{Keys: bson.D{{Key: "user_id", Value: 1}}},
	})

	return &RoomRepository{
		rooms:   db.Collection("rooms"),
		members: members,
	}
}

// Get new room
func (r *RoomRepository) Create(ctx context.Context, room *model.Room) error {
	room.ID = primitive.NewObjectID()
	room.IsActive = true
	room.CreatedAt = time.Now()
	_, err := r.rooms.InsertOne(ctx, room)
	return err
}

// Find room if u have ID
func (r *RoomRepository) FindByID(ctx context.Context, id primitive.ObjectID) (*model.Room, error) {
	var room model.Room
	err := r.rooms.FindOne(ctx, bson.M{"_id": id}).Decode(&room)
	if err != nil {
		return nil, err
	}
	return &room, nil
}

// Get allroom of 1 user
func (r *RoomRepository) FindByOwner(ctx context.Context, ownerID primitive.ObjectID) ([]model.Room, error) {
	cursor, err := r.rooms.Find(ctx, bson.M{"owner.id": ownerID})
	if err != nil {
		return nil, err
	}
	var rooms []model.Room
	if err := cursor.All(ctx, &rooms); err != nil {
		return nil, err
	}
	return rooms, nil
}

// Add member to room
func (r *RoomRepository) AddMember(ctx context.Context, member *model.RoomMember) error {
	member.ID = primitive.NewObjectID()
	member.JoinedAt = time.Now()
	_, err := r.members.InsertOne(ctx, member)
	return err
}

// Delete member get out room
func (r *RoomRepository) RemoveMember(ctx context.Context, roomID, userID primitive.ObjectID) error {
	_, err := r.members.DeleteOne(ctx, bson.M{
		"room_id": roomID,
		"user_id": userID,
	})
	return err
}

// Check user have in a room
func (r *RoomRepository) IsMember(ctx context.Context, roomID, userID primitive.ObjectID) bool {
	count, err := r.members.CountDocuments(ctx, bson.M{
		"room_id": roomID,
		"user_id": userID,
	})
	return err == nil && count > 0
}

// Get list members of room
func (r *RoomRepository) GetMembers(ctx context.Context, roomID primitive.ObjectID) ([]model.RoomMember, error) {
	cursor, err := r.members.Find(ctx, bson.M{"room_id": roomID})
	if err != nil {
		return nil, err
	}
	var members []model.RoomMember
	cursor.All(ctx, &members)
	return members, nil
}

// Get role of user in a room
func (r *RoomRepository) GetMemberRole(ctx context.Context, roomID, userID primitive.ObjectID) (string, error) {
	var member model.RoomMember
	err := r.members.FindOne(ctx, bson.M{
		"room_id": roomID,
		"user_id": userID,
	}, options.FindOne().SetProjection(bson.M{"role": 1})).Decode(&member)
	if err != nil {
		return "", err
	}
	return member.Role, nil
}
