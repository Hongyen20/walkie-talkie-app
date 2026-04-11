package repository

import (
	"context"
	"time"
	"walkie-talkie-app/internal/model"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

type ChannelRepository struct {
	col *mongo.Collection
}

func NewChannelRepository(db *mongo.Database) *ChannelRepository {
	return &ChannelRepository{col: db.Collection("channels")}
}

// Create new channel
func (r *ChannelRepository) Create(ctx context.Context, ch *model.Channel) error {
	ch.ID = primitive.NewObjectID()
	ch.CreatedAt = time.Now()
	ch.Members = []primitive.ObjectID{}
	_, err := r.col.InsertOne(ctx, ch)
	return err
}

// Get all channel of room
func (r *ChannelRepository) FindByRoom(ctx context.Context, roomID primitive.ObjectID) ([]model.Channel, error) {
	cursor, err := r.col.Find(ctx, bson.M{"room_id": roomID})
	if err != nil {
		return nil, err
	}
	var channels []model.Channel
	cursor.All(ctx, &channels)
	return channels, nil
}

// Find channel by ID
func (r *ChannelRepository) FindByID(ctx context.Context, id primitive.ObjectID) (*model.Channel, error) {
	var ch model.Channel
	err := r.col.FindOne(ctx, bson.M{"_id": id}).Decode(&ch)
	if err != nil {
		return nil, err
	}
	return &ch, nil
}

// Lock/Unlock channel
func (r *ChannelRepository) SetLocked(ctx context.Context, channelID primitive.ObjectID, locked bool) error {
	_, err := r.col.UpdateOne(ctx,
		bson.M{"_id": channelID},
		bson.M{"$set": bson.M{"is_locked": locked}},
	)
	return err
}

// Add member to channel
func (r *ChannelRepository) AddMember(ctx context.Context, channelID, userID primitive.ObjectID) error {
	_, err := r.col.UpdateOne(ctx,
		bson.M{"_id": channelID},
		bson.M{"$addToSet": bson.M{"members": userID}},
	)
	return err
}

// Delete memeber get out channel
func (r *ChannelRepository) RemoveMember(ctx context.Context, channelID, userID primitive.ObjectID) error {
	_, err := r.col.UpdateOne(ctx,
		bson.M{"_id": channelID},
		bson.M{"$pull": bson.M{"members": userID}},
	)
	return err
}

//Delete channel
func (r *ChannelRepository) DeleteChannel(ctx context.Context, channelID primitive.ObjectID) error{
	_, err := r.col.DeleteOne(ctx, bson.M{"_id": channelID})
	return err
}
