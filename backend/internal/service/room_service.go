package service

import (
	"context"
	"errors"
	"walkie-talkie-app/internal/model"
	"walkie-talkie-app/internal/repository"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

type RoomService struct {
	roomRepo    *repository.RoomRepository
	channelRepo *repository.ChannelRepository
}

func NewRoomService(roomRepo *repository.RoomRepository, channelRepo *repository.ChannelRepository) *RoomService {
	return &RoomService{roomRepo: roomRepo, channelRepo: channelRepo}
}

// Create new room
func (s *RoomService) CreateRoom(ctx context.Context, ownerID primitive.ObjectID, name string) (*model.Room, error) {
	room := &model.Room{
		Name:        name,
		OwnerID:     ownerID,
		InvitedCode: generateInviteCode(),
	}
	if err := s.roomRepo.Create(ctx, room); err != nil {
		return nil, err
	}

	//Auto add owner to room_members
	member := &model.RoomMember{
		RoomID: room.ID,
		UserID: ownerID,
		Role:   "owner",
	}
	s.roomRepo.AddMember(ctx, member)
	return room, nil
}

// Add member to room (just owner can add member)
func (s *RoomService) AddMember(ctx context.Context, roomID, ownerID, newUserID primitive.ObjectID) error {
	role, err := s.roomRepo.GetMemberRole(ctx, roomID, ownerID)
	if err != nil || role != "owner" {
		return errors.New("Only owner can add members")
	}
	if s.roomRepo.IsMember(ctx, roomID, newUserID) {
		return errors.New("User already in room")
	}
	member := &model.RoomMember{
		RoomID: roomID,
		UserID: newUserID,
		Role:   "member",
	}
	return s.roomRepo.AddMember(ctx, member)
}

// Kick member (just owner can do that)
func (s *RoomService) RemoveMember(ctx context.Context, roomID, ownerID, targetUserID primitive.ObjectID) error {
	role, err := s.roomRepo.GetMemberRole(ctx, roomID, ownerID)
	if err != nil || role != "owner" {
		return errors.New("Only owner can remove members")
	}
	return s.roomRepo.RemoveMember(ctx, roomID, targetUserID)
}

// Create Channel (just owner can do that)
func (s *RoomService) CreateChannel(ctx context.Context, roomID, ownerID primitive.ObjectID, name string) (*model.Channel, error) {
	role, err := s.roomRepo.GetMemberRole(ctx, roomID, ownerID)
	if err != nil || role != "owner" {
		return nil, errors.New("Only owner can create channels")
	}

	ch := &model.Channel{
		RoomID:    roomID,
		Name:      name,
		CreatedBy: ownerID,
		IsLocked:  false,
	}
	if err := s.channelRepo.Create(ctx, ch); err != nil {
		return nil, err
	}
	return ch, nil
}

// Lock/Unlock channel (just owner)
func (s *RoomService) SetChannelLocked(ctx context.Context, roomID, ownerID, channelID primitive.ObjectID, locked bool) error {
	role, err := s.roomRepo.GetMemberRole(ctx, roomID, ownerID)
	if err != nil || role != "owner" {
		return errors.New("Only owner can lock/unlock channels")
	}
	return s.channelRepo.SetLocked(ctx, channelID, locked)
}

// Get list channels of room
func (s *RoomService) GetChannels(ctx context.Context, roomID primitive.ObjectID) ([]model.Channel, error) {
	return s.channelRepo.FindByRoom(ctx, roomID)
}

func (s *RoomService) GetRoomsByOwner(ctx context.Context, ownerID primitive.ObjectID) ([]model.Room, error) {
    return s.roomRepo.FindByOwner(ctx, ownerID)
}

// Get all room, user had join
func (s *RoomService) GetRoomsByUser(ctx context.Context, userID primitive.ObjectID) ([]model.RoomWithRole, error) {
    return s.roomRepo.FindByMember(ctx, userID)
}

func (s *RoomService) JoinByInviteCode(ctx context.Context, userID primitive.ObjectID, code string) (*model.Room, error){
	//Find room by invite code
	room, err := s.roomRepo.FindByInviteCode(ctx, code)
	if err != nil{
		return nil, errors.New("Invalid invite code")
	}

	//Check user had join room???
	if s.roomRepo.IsMember(ctx, room.ID, userID){
		return nil, errors.New("You're already in this room.")
	}

	//Add user into room
	member := &model.RoomMember{
		RoomID: room.ID,
		UserID: userID,
		Role: "member",
	}
	if err := s.roomRepo.AddMember(ctx, member); err != nil {
		return nil, err
	}
	return room, nil
}

func (s *RoomService) IsMember(ctx context.Context, roomID, userID primitive.ObjectID) bool {
    return s.roomRepo.IsMember(ctx, roomID, userID)
}

func (s *RoomService) DeleteRoom(ctx context.Context, roomID, userID primitive.ObjectID) error{
	role, err := s.roomRepo.GetMemberRole(ctx, roomID, userID)
	if err != nil || role != "owner"{
		return errors.New("Only owner can delete room")
	}
	return s.roomRepo.DeleteRoom(ctx, roomID)
}

func (s *RoomService) DeleteChannel(ctx context.Context, roomID, channelID, userID primitive.ObjectID) error{
	role, err := s.roomRepo.GetMemberRole(ctx, roomID, userID)
	if err != nil || role != "owner"{
		return errors.New("Only owner can delete channel")
	}
	return s.channelRepo.DeleteChannel(ctx, channelID)
}

func (s *RoomService) LeaveRoom(ctx context.Context, roomID, userID primitive.ObjectID) error{
	role, err := s.roomRepo.GetMemberRole(ctx, roomID, userID)
	if err != nil{
		return errors.New("You aren't in this room")
	}
	if role == "owner"{
		return errors.New("Owner can't leave room, You shoud delete it instead")
	}
	return s.roomRepo.RemoveMember(ctx, roomID, userID)
}