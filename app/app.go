package app

import (
	"context"
	"crypto/elliptic"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/SherClockHolmes/webpush-go"
	"github.com/google/uuid"
)

var curve = elliptic.P256()

type Subscription struct {
	Endpoint string `json:"endpoint"`
	P256dh   []byte `json:"p256dh"`
	Auth     []byte `json:"auth"`
}

type Post struct {
	ID     uuid.UUID `json:"id" datastore:"-"`
	Author string    `json:"author"`
	Text   string    `json:"text"`
	Time   time.Time `json:"time"`
}

type KeyPair struct {
	pk string
	sk string
}

type App struct {
	db    DB
	tasks Tasks
	auth  Auth
	http  HttpHandler
}

type User struct {
	UUID uuid.UUID
	Name string
}

func New(db DB, tasks Tasks, auth Auth, handler HttpHandler) App {
	return App{db, tasks, auth, handler}
}

func (app *App) Run(port string) error {
	app.http.HandleFunc("/vapid-public-key", app.getPublicKey)
	app.http.HandleFunc("/api/subscription", app.putSubscription)
	app.http.HandleFunc("/api/post", app.putPost)
	app.http.HandleFunc("/api/posts", app.getPosts)

	return app.http.ListenAndServe(":"+port, nil)
}

func (app *App) getPublicKey(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	k, err := app.db.GetKey(ctx)

	log.Printf("vapid key is: %v", k)
	// no key yet? let's build it now
	if err == ErrNoSuchEntity {
		sk, pk, err2 := webpush.GenerateVAPIDKeys()
		if err2 != nil {
			msg := fmt.Sprintf("could not create VAPID keys (%v)", err)
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(msg))
			return
		}
		k.pk = pk
		k.sk = sk
		err2 = app.db.PutKey(ctx, k)
		if err2 != nil {
			msg := fmt.Sprintf("could not save VAPID keys (%v)", err)
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(msg))
			return
		}
	}

	w.Write([]byte(k.pk))
}

func (app *App) putSubscription(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	u, err := app.getUser(ctx)
	if err != nil {
		msg := fmt.Sprintf("could not get user (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	decoder := json.NewDecoder(req.Body)
	s := Subscription{}
	err = decoder.Decode(&s)
	if err != nil {
		msg := fmt.Sprintf("could not read json body key (%v)", err)
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(msg))
		return
	}

	err = app.db.PutSubscription(ctx, s, u)
	if err != nil {
		msg := fmt.Sprintf("could not save subscription (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}
}

func (app *App) getPosts(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	ps, err := app.db.GetPosts(ctx)
	if err != nil {
		msg := fmt.Sprintf("could not get posts from db: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	json, err := json.Marshal(&ps)
	if err != nil {
		msg := fmt.Sprintf("could not marshal posts (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}
	w.Write(json)
}

func (app *App) putPost(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	u, err := app.getUser(ctx)
	if err != nil {
		msg := fmt.Sprintf("could not get user (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	decoder := json.NewDecoder(req.Body)
	p := Post{
		Author: u.Name,
		Time:   time.Now(),
		ID:     uuid.New(),
	}
	err = decoder.Decode(&p)
	if err != nil {
		msg := fmt.Sprintf("could not read json body key (%v)", err)
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(msg))
		return
	}

	err = app.db.PutPost(ctx, p)
	if err != nil {
		msg := fmt.Sprintf("could not save post (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	json, err := json.Marshal(&p)
	if err != nil {
		msg := fmt.Sprintf("could not marshal post (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}
	w.WriteHeader(http.StatusCreated)
	w.Write(json)

	// send push
	err = app.tasks.Notify(ctx)
	if err != nil {
		log.Printf("could not notify clients: %v", err)
	}
}

func (app *App) getUser(ctx context.Context) (User, error) {
	ru := app.auth.Current(ctx)

	u, err := app.db.GetUser(ctx, ru.UUID)
	if err == ErrNoSuchEntity {
		err2 := app.db.PutUser(ctx, u)
		if err2 != nil {
			return User{}, err2
		}
	} else if err != nil {
		return User{}, err
	}

	return u, nil
}

func (app *App) notifyAll(ctx context.Context, _ string) error {
	// get server keys
	k, err := app.db.GetKey(ctx)
	if err != nil {
		return fmt.Errorf("could not get server key: %v", err)
	}
	// get user keys
	ss, err := app.db.GetSubscriptions(ctx)
	if err != nil {
		return err
	}

	log.Printf("notifying 1 user on %d subscriptions", len(ss))

	// send pushes to each sub
	for _, s := range ss {
		ws := webpush.Subscription{}
		ws.Endpoint = s.Endpoint
		ws.Keys = webpush.Keys{}
		ws.Keys.Auth = base64.RawURLEncoding.EncodeToString(s.Auth)
		ws.Keys.P256dh = base64.RawURLEncoding.EncodeToString(s.P256dh)

		// Send Notification
		res, err := webpush.SendNotification([]byte("msg-sync"), &ws, &webpush.Options{
			Subscriber:      "<mh@lambdasoup.com>",
			VAPIDPrivateKey: k.sk,
			VAPIDPublicKey:  k.pk,
			TTL:             30,
		})
		log.Printf("%v", res)
		if err != nil {
			log.Printf("could not send notification: %v", err)
		}
	}

	return nil
}
