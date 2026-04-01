package model

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)
type User struct{
	ID 			primitive.ObjectID 	`bson:"_id,omitempty"	json:"id"`
	Username	string				`bson:"username"		json:"username"`
	Password 	string				`bson:"password"		json:"-"`
	DisplayName	string				`bson:"display_name"	json:"display_name"`
	InviteCode	string				`bson:"invite_code"		json:"invite_code"`
	CreatedAt	time.Time			`bson:"created_at"		json:"created_at"`
	LastSeen	time.Time 			`bson:"last_seen"		json:"last_seen"`
}