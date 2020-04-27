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
	PK string
	SK string
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
	app.HandleFuncAuthed("/api/subscription", app.putSubscription)
	app.http.HandleFunc("/api/post", app.putPost)
	app.http.HandleFunc("/api/posts", app.getPosts)
	app.http.HandleFunc("/api/auth", app.postAuth)

	return app.http.ListenAndServe(":"+port, nil)
}

func (app *App) HandleFuncAuthed(path string, handle func(http.ResponseWriter,
	*http.Request)) {

	app.http.HandleFunc(path, func(w http.ResponseWriter, req *http.Request) {
		auth := req.Header["Authorization"]
		if auth[0] != "dummy-token" {
			w.WriteHeader(http.StatusUnauthorized)
			w.Write([]byte("no/wrong authorization header provided"))
			return
		}
		handle(w, req)
	})
}

func (app *App) getPublicKey(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	k, err := app.db.GetKey(ctx)

	// no key yet? let's build it now
	if err == ErrNoSuchEntity {
		sk, pk, err2 := webpush.GenerateVAPIDKeys()
		if err2 != nil {
			msg := fmt.Sprintf("could not create VAPID keys (%v)", err)
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(msg))
			return
		}
		log.Printf("key: %v", k)
		k.PK = pk
		k.SK = sk
		err2 = app.db.PutKey(ctx, k)
		if err2 != nil {
			msg := fmt.Sprintf("could not save VAPID keys (%v)", err)
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(msg))
			return
		}
	}

	w.Write([]byte(k.PK))
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
		msg := fmt.Sprintf("could not unmarshal json body: %v", err)
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

func (app *App) postAuth(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	nt := &NameToken{}
	err := json.NewDecoder(req.Body).Decode(nt)
	if err != nil {
		msg := fmt.Sprintf("could not decode json body: %v", err)
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(msg))
		return
	}

	nt, err = app.auth.Login(ctx, nt.Name)
	if err != nil {
		msg := fmt.Sprintf("could not get posts from db: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	json, err := json.Marshal(nt)
	if err != nil {
		msg := fmt.Sprintf("could not marshal posts (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}
	w.Write(json)
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
			VAPIDPrivateKey: k.SK,
			VAPIDPublicKey:  k.PK,
			TTL:             30,
		})
		log.Printf("%v", res)
		if err != nil {
			log.Printf("could not send notification: %v", err)
		}
	}

	return nil
}
