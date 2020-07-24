package app

import (
	"context"
	"crypto/elliptic"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	"github.com/SherClockHolmes/webpush-go"
	"github.com/google/uuid"
)

var curve = elliptic.P256()

type Subscription struct {
	UserID   uuid.UUID `json:"-" datastore:"-"`
	Endpoint string    `json:"endpoint"`
	P256dh   []byte    `json:"p256dh"`
	Auth     []byte    `json:"auth"`
}

type Post struct {
	ID   uuid.UUID `json:"id" datastore:"-"`
	User User      `json:"user"`
	Text string    `json:"text"`
	Time Time      `json:"time"`
}

type KeyPair struct {
	PK string
	SK string
}

type App struct {
	db   DB
	user UserService
	http HttpHandler
}

func New(db DB, user UserService, handler HttpHandler) App {
	return App{db, user, handler}
}

func (app *App) Run(port string) error {
	app.http.HandleFunc("/vapid-public-key", app.getPublicKey)
	app.HandleFuncAuthed("/api/subscription", methodHandler{
		post: app.postSubscription,
		get:  app.getSubscription,
	}.handle)
	app.HandleFuncAuthed("/api/posts", methodHandler{
		post: app.postPosts,
		get:  app.getPosts,
	}.handle)
	app.http.HandleFunc("/api/login", app.login)

	return app.http.ListenAndServe(":"+port, nil)
}

type methodHandler struct {
	get  func(http.ResponseWriter, *http.Request)
	post func(http.ResponseWriter, *http.Request)
}

func (mh methodHandler) handle(w http.ResponseWriter, req *http.Request) {
	switch req.Method {
	case "GET":
		if mh.get != nil {
			mh.get(w, req)
			return
		}
	case "POST":
		if mh.post != nil {
			mh.post(w, req)
			return
		}
	default:
	}

	w.WriteHeader(http.StatusMethodNotAllowed)
}

func (app *App) HandleFuncAuthed(path string, handle func(http.ResponseWriter,
	*http.Request)) {

	app.http.HandleFunc(path, func(w http.ResponseWriter, req *http.Request) {
		ctx, err := app.user.Decorate(req)
		if err != nil {
			w.WriteHeader(http.StatusUnauthorized)
			msg := fmt.Sprintf("no/wrong authorization header provided (%v)", err)
			w.Write([]byte(msg))
			return
		}
		handle(w, req.WithContext(ctx))
	})
}

func (app *App) getPublicKey(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	k, err := app.db.GetKey(ctx)

	// no key yet? let's build it now
	switch err {
	case ErrNoSuchEntity:
		sk, pk, err2 := webpush.GenerateVAPIDKeys()
		if err2 != nil {
			msg := fmt.Sprintf("could not create VAPID keypair (%v)", err2)
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(msg))
			return
		}
		k.PK = pk
		k.SK = sk
		err2 = app.db.PutKey(ctx, k)
		if err2 != nil {
			msg := fmt.Sprintf("could not save VAPID keypair (%v)", err2)
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(msg))
			return
		}
		// all ok
	case nil:
		w.Write([]byte(k.PK))
	// other error
	default:
		msg := fmt.Sprintf("could not get VAPID keypair (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

}

func (app *App) postSubscription(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	s := Subscription{}
	decoder := json.NewDecoder(req.Body)
	err := decoder.Decode(&s)
	if err != nil {
		msg := fmt.Sprintf("could not unmarshal json body: %v", err)
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(msg))
		return
	}

	uid := app.user.Current(ctx)
	s.UserID = uid

	err = app.db.CreateSubscription(ctx, s)
	if err != nil {
		msg := fmt.Sprintf("could not create subscription (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	w.WriteHeader(http.StatusCreated)
}
func (app *App) getSubscription(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	uid := app.user.Current(ctx)
	_, err := app.db.ReadSubscription(ctx, uid)
	switch err {
	case nil:
		w.WriteHeader(http.StatusNoContent)
	case ErrNoSuchEntity:
		msg := fmt.Sprintf("no subscription found (%v)", err)
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte(msg))
		return
	default:
		msg := fmt.Sprintf("could not read subscription (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}
}

func (app *App) register(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	u := User{}
	err := json.NewDecoder(req.Body).Decode(&u)
	if err != nil {
		msg := fmt.Sprintf("could not decode json body: %v", err)
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(msg))
		return
	}

	u, err = app.user.Register(ctx, u.Name)
	if err != nil {
		msg := fmt.Sprintf("could not get posts from db: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	json, err := json.Marshal(u)
	if err != nil {
		msg := fmt.Sprintf("could not marshal posts (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}
	w.Write(json)
}

func (app *App) login(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	u := User{}
	err := json.NewDecoder(req.Body).Decode(&u)
	if err != nil {
		msg := fmt.Sprintf("could not decode json body: %v", err)
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(msg))
		return
	}

	u2, err := app.user.GetUserByName(ctx, u.Name)
	if err != nil {
		// just assume the user is missing, other errors will show up again soon
		u2, err = app.user.Register(ctx, u.Name)
		if err != nil {
			msg := fmt.Sprintf("could not get user from db: %v", err)
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(msg))
			return
		}
	}

	r := struct {
		User  User   `json:"user"`
		Token string `json:"token"`
	}{User: u2, Token: u2.ID.String()}

	json, err := json.Marshal(r)
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

	ps, err := app.db.ReadPosts(ctx)
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

func (app *App) postPosts(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	u, err := app.getUser(ctx)
	if err != nil {
		msg := fmt.Sprintf("could not get user (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	decoder := json.NewDecoder(req.Body)
	ps := []Post{}
	err = decoder.Decode(&ps)
	if err != nil {
		msg := fmt.Sprintf("could not read json body key (%v)", err)
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(msg))
		return
	}

	// TODO decorate with server side data (user, time, id)
	for _, p := range ps {
		p.User = u
		p.ID = uuid.New()
		err = app.db.PutPost(ctx, p)
		if err != nil {
			msg := fmt.Sprintf("could not save posts (%v)", err)
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(msg))
			return
		}
	}

	// send push
	err = app.notifyAll(ctx)
	if err != nil {
		msg := fmt.Sprintf("could not notify clients (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (app *App) getUser(ctx context.Context) (User, error) {
	id := app.user.Current(ctx)

	u, err := app.db.GetUser(ctx, id)
	return u, err
}

func (app *App) notifyAll(ctx context.Context) error {
	// get server keys
	k, err := app.db.GetKey(ctx)
	if err != nil {
		return fmt.Errorf("could not get server key: %v", err)
	}
	// get user keys
	ss, err := app.db.ReadAllSubscriptions(ctx)
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
