package model

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

type Room struct{
	ID			primitive.ObjectID	`bson:"_id,omitempty"	json:"id"`
	Name		string				`bson:"name"			json:"name"`
	OwnerID		primitive.ObjectID	`bson:"owner_id"		json:"owner_id"`
	InvitedCode	string				`bson:"invite_code"		json:"invite_code"`
	IsActive	bool				`bson:"is_active"		json:"is_active"`
	CreatedAt	time.Time			`bson:"created_at"		json:"created_at"`
}

type Channel struct{
	ID			primitive.ObjectID		`bson:"_id,omitempty"	json:"id"`	
	RoomID		primitive.ObjectID		`bson:"room_id"			json:"room_id"`
	Name		string					`bson:"name"			json:"name"`	
	CreatedBy	primitive.ObjectID		`bson:"created_by"		json:"created_by"`
	IsLocked	bool					`bson:"is_locked"		json:"is_locked"`
	Members		[]primitive.ObjectID	`bson:"mebers"			json:"member"`
	CreatedAt	time.Time				`bson:"created_at"		json:"created_at"`
}

type RoomMember struct{
	ID 			primitive.ObjectID	`bson:"_id,omitempty"	json:"id"`
	RoomID		primitive.ObjectID	`bson:"room_id"			json:"room_id`
	UserID		primitive.ObjectID	`bson:"user_id"			json:"user_id`
	Role		string				`bson:"role"			json:"role"`  //Owner || member
	JoinedAt	time.Time			`bson:"joined_at"		json:"joined_at"`
}


type RoomWithRole struct {
    ID         primitive.ObjectID `bson:"_id,omitempty" json:"id"`
    Name       string             `bson:"name"          json:"name"`
    OwnerID    primitive.ObjectID `bson:"owner_id"      json:"owner_id"`
    InviteCode string             `bson:"invite_code"   json:"invite_code"`
    IsActive   bool               `bson:"is_active"     json:"is_active"`
    CreatedAt  time.Time          `bson:"created_at"    json:"created_at"`
    Role       string             `bson:"-"             json:"role"` // owner | member
}

type MemberInfo struct {
    UserID      primitive.ObjectID `bson:"user_id"   json:"user_id"`
    Username    string             `bson:"username"  json:"username"`
    DisplayName string             `bson:"display_name" json:"display_name"`
    Role        string             `bson:"-"         json:"role"`
}