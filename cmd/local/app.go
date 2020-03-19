package main

import (
	"context"
	"log"
	"net/http"

	"github.com/google/uuid"
	"github.com/maxhille/elm-pwa-example/server"
)

func main() {
	// for local dev
	http.Handle("/", http.FileServer(newPublicFileSystem()))

	srv := server.New(
		&LocalDB{},
		&LocalTasks{},
		&LocalAuth{},
	)

	log.Print("Listening on port 8080")
	if err := srv.Run("8080"); err != nil {
		log.Fatal(err)
	}

}

type publicFileSystem struct {
	base  http.Dir
	build http.Dir
}

func (fs *publicFileSystem) Open(name string) (http.File, error) {
	log.Printf("serve file: %v", name)
	if name == "/elm.js" {
		return fs.build.Open(name)
	}

	return fs.base.Open(name)
}

func newPublicFileSystem() *publicFileSystem {
	return &publicFileSystem{
		base:  http.Dir("./"),
		build: http.Dir("./build"),
	}
}

type LocalDB struct {
	server.DB
}

func (db *LocalDB) GetUser(ctx context.Context, id uuid.UUID) (server.User,
	error) {
	// TODO implement
	return server.User{}, nil
}

func (db *LocalDB) PutUser(ctx context.Context, u server.User) error {
	// TODO implement
	return nil
}
func (db *LocalDB) PutSubscription(ctx context.Context, s server.Subscription,
	u server.User) error {
	// TODO implement
	return nil
}

func (db *LocalDB) GetSubscriptions(ctx context.Context) ([]server.Subscription,
	error) {
	// TODO implement
	return []server.Subscription{}, nil
}

func (db *LocalDB) GetPublicKey(ctx context.Context) (server.KeyPair, error) {
	// TODO implement
	return server.KeyPair{}, nil
}

func (db *LocalDB) GetPosts(ctx context.Context) ([]server.Post, error) {
	// TODO implement
	return []server.Post{}, nil
}

func (db *LocalDB) PutPost(ctx context.Context, p server.Post) error {
	// TODO implement
	return nil
}

type LocalTasks struct {
	server.Tasks
}

func (ct *LocalTasks) Notify(ctx context.Context) error {
	// TODO notify
	return nil
}

type LocalAuth struct {
	server.Auth
}

func (ga *LocalAuth) Current(ctx context.Context) server.User {
	// TODO migrate somewhere new, was
	//	return guser.Current(ctx)
	return server.User{}
}
