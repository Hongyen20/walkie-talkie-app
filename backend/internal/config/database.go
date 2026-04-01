package config

import (
	"context"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var DB *mongo.Database

func ConnectMongo(uri string, dbName string){
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
	if err != nil{
		log.Fatal("MongoDB connect error:", err)
	}

	// Ping to check connection
	if err := client.Ping(ctx, nil); err != nil{
		log.Fatal("MongoDB ping error:  ", err)
	}

	DB = client.Database(dbName)
	log.Println("[DB] Connected to MonggoDB:", dbName)
}