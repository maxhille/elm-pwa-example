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
	UserID   uuid.UUID `json:-`
	Endpoint string    `json:"endpoint"`
	P256dh   []byte    `json:"p256dh"`
	Auth     []byte    `json:"auth"`
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
	user  UserService
	http  HttpHandler
}

func New(db DB, tasks Tasks, user UserService, handler HttpHandler) App {
	return App{db, tasks, user, handler}
}

func (app *App) Run(port string) error {
	app.http.HandleFunc("/vapid-public-key", app.getPublicKey)
	app.HandleFuncAuthed("/api/subscription", methodHandler{
		post: app.postSubscription,
		get:  app.getSubscription,
	}.handle)
	app.http.HandleFunc("/api/post", app.putPost)
	app.http.HandleFunc("/api/posts", app.getPosts)
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
		Name  string `json:"name"`
		Token string `json:"token"`
	}{Name: u2.Name, Token: u2.ID.String()}

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
	id := app.user.Current(ctx)

	u, err := app.db.GetUser(ctx, id)
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
