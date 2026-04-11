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
	cursor, err := r.rooms.Find(ctx, bson.M{"owner_id": ownerID})
	if err != nil {
		return []model.Room{}, nil // return to null array
	}
	var rooms []model.Room
	if err := cursor.All(ctx, &rooms); err != nil {
		return []model.Room{}, nil
	}
	if rooms == nil {
		return []model.Room{}, nil // not return nil
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
func (r *RoomRepository) GetMembersWithInfo(ctx context.Context, db *mongo.Database, roomID primitive.ObjectID) ([]model.MemberInfo, error) {
	cursor, err := r.members.Find(ctx, bson.M{"room_id": roomID})
	if err != nil {
		return []model.MemberInfo{}, nil
	}
	var members []model.RoomMember
	cursor.All(ctx, &members)

	usersCol := db.Collection("users")
	result := make([]model.MemberInfo, 0)

	for _, m := range members {
		var user struct {
			Username    string `bson:"username"`
			DisplayName string `bson:"display_name"`
		}
		usersCol.FindOne(ctx, bson.M{"_id": m.UserID}).Decode(&user)
		result = append(result, model.MemberInfo{
			UserID:      m.UserID,
			Username:    user.Username,
			DisplayName: user.DisplayName,
			Role:        m.Role,
		})
	}
	return result, nil
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

// Find room by invite code
func (r *RoomRepository) FindByInviteCode(ctx context.Context, code string) (*model.Room, error) {
	var room model.Room
	err := r.rooms.FindOne(ctx, bson.M{"invite_code": code}).Decode(&room)
	if err != nil {
		return nil, err
	}
	return &room, nil
}

// Get all room when user join
func (r *RoomRepository) FindByMember(ctx context.Context, userID primitive.ObjectID) ([]model.RoomWithRole, error) {
	cursor, err := r.members.Find(ctx, bson.M{"user_id": userID})
	if err != nil {
		return []model.RoomWithRole{}, nil
	}
	var members []model.RoomMember
	cursor.All(ctx, &members)

	if len(members) == 0 {
		return []model.RoomWithRole{}, nil
	}

	// Map role theo roomID
	roleMap := make(map[primitive.ObjectID]string)
	roomIDs := make([]primitive.ObjectID, 0)
	for _, m := range members {
		roomIDs = append(roomIDs, m.RoomID)
		roleMap[m.RoomID] = m.Role
	}

	cursor2, err := r.rooms.Find(ctx, bson.M{"_id": bson.M{"$in": roomIDs}})
	if err != nil {
		return []model.RoomWithRole{}, nil
	}
	var rooms []model.Room
	cursor2.All(ctx, &rooms)

	// Gắn role vào từng room
	result := make([]model.RoomWithRole, 0)
	for _, room := range rooms {
		result = append(result, model.RoomWithRole{
			ID:         room.ID,
			Name:       room.Name,
			OwnerID:    room.OwnerID,
			InviteCode: room.InvitedCode,
			IsActive:   room.IsActive,
			CreatedAt:  room.CreatedAt,
			Role:       roleMap[room.ID],
		})
	}
	return result, nil
}

// Delete Room
func (r *RoomRepository) DeleteRoom(ctx context.Context, roomID primitive.ObjectID) error {
	_, err := r.rooms.DeleteOne(ctx, bson.M{"_id": roomID})
	//Delete all members in this Room
	r.members.DeleteMany(ctx, bson.M{"room_id": roomID})
	return err

}
