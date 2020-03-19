package main

import (
	"fmt"
	"log"
	"os"

	"golang.org/x/net/context"

	"github.com/google/uuid"
	"github.com/maxhille/elm-pwa-example/server"

	cloudtasks "cloud.google.com/go/cloudtasks/apiv2beta3"
	"cloud.google.com/go/datastore"
	taskspb "google.golang.org/genproto/googleapis/cloud/tasks/v2beta3"
)

func main() {
	srv := server.New(
		&DatastoreDB{},
		&Cloudtasks{},
		&GoogleAuth{},
	)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
		log.Printf("Defaulting to port %s", port)
	}

	log.Printf("Listening on port %s", port)
	if err := srv.Run(port); err != nil {
		log.Fatal(err)
	}
}

type user struct {
	Key   *datastore.Key
	Email string
	Name  string
}

type DatastoreDB struct {
	server.DB
}

func (db *DatastoreDB) GetUser(ctx context.Context, id uuid.UUID) (server.User, error) {
	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		return server.User{}, fmt.Errorf("could not create datastore client (%v)", err)
	}

	uk := datastore.NameKey("User", id.String(), nil)
	u := server.User{}
	err = dsc.Get(ctx, uk, &u)
	return u, err
}

func (db *DatastoreDB) PutUser(ctx context.Context, u server.User) error {
	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		return fmt.Errorf("could not create datastore client (%v)", err)
	}

	uk := datastore.NameKey("User", u.UUID.String(), nil)
	_, err = dsc.Put(ctx, uk, &u)
	return err
}
func (db *DatastoreDB) PutSubscription(ctx context.Context, s server.Subscription, u server.User) error {
	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		return fmt.Errorf("could not create datastore client (%v)", err)
	}

	uk := datastore.NameKey("User", u.UUID.String(), nil)
	sk := datastore.IncompleteKey("Subscription", uk)
	_, err = dsc.Put(ctx, sk, &s)
	return err
}

func (db *DatastoreDB) GetSubscriptions(ctx context.Context) ([]server.Subscription, error) {
	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		return nil, fmt.Errorf("could not create datastore client (%v)", err)
	}

	q := datastore.NewQuery("Subscription")
	ss := []server.Subscription{}
	_, err = dsc.GetAll(ctx, q, &ss)
	return ss, err
}

func (db *DatastoreDB) GetPublicKey(ctx context.Context) (server.KeyPair, error) {
	k := server.KeyPair{}
	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		return k, fmt.Errorf("could not create datastore client (%v)", err)
	}

	kk := datastore.NameKey("KeyPair", "vapid-keypair", nil)
	err = dsc.Get(ctx, kk, &k)
	return k, err
}

func (db *DatastoreDB) GetPosts(ctx context.Context) ([]server.Post, error) {
	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		return nil, fmt.Errorf("could not create datastore client (%v)", err)
	}

	ps := []server.Post{}
	q := datastore.NewQuery("Post")
	pks, err := dsc.GetAll(ctx, q, &ps)
	if err != nil {
		return nil, fmt.Errorf("could not get posts from db: %v", err)
	}

	for i, _ := range ps {
		ps[i].ID = uuid.MustParse(pks[i].Name)
	}
	return ps, nil
}

func (db *DatastoreDB) PutPost(ctx context.Context, p server.Post) error {
	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		return fmt.Errorf("could not create datastore client (%v)", err)
	}

	pik := datastore.NameKey("Post", p.ID.String(), nil)
	_, err = dsc.Put(ctx, pik, &p)
	return err
}

type Cloudtasks struct {
	server.Tasks
}

func (ct *Cloudtasks) Notify(ctx context.Context) error {
	ctc, err := cloudtasks.NewClient(ctx)
	if err != nil {
		return fmt.Errorf("could not create cloud tasks client (%v)", err)
	}

	treq := &taskspb.CreateTaskRequest{
		// TODO complete, was
		// delay.Func("notify-all", notifyAll)
	}
	_, err = ctc.CreateTask(ctx, treq)
	return err
}

type GoogleAuth struct {
	server.Auth
}

func (ga *GoogleAuth) Current(ctx context.Context) server.User {
	// TODO migrate somewhere new, was
	//	return guser.Current(ctx)
	return server.User{}
}
