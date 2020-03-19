package server

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
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
	X []byte
	Y []byte
	D []byte
}

type Server struct {
	db    DB
	tasks Tasks
	auth  Auth
}

type User struct {
	UUID uuid.UUID
	Name string
}

func New(db DB, tasks Tasks, auth Auth) Server {
	return Server{db, tasks, auth}
}

func (srv *Server) Run(port string) error {
	http.HandleFunc("/vapid-public-key", srv.getPublicKey)
	http.HandleFunc("/api/subscription", srv.putSubscription)
	http.HandleFunc("/api/post", srv.putPost)
	http.HandleFunc("/api/posts", srv.getPosts)

	return http.ListenAndServe(":"+port, nil)
}

func (srv *Server) getPublicKey(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	k, err := srv.db.GetKey(ctx)

	// no key yet? let's build it now
	if err == ErrNoSuchEntity {
		key, err2 := ecdsa.GenerateKey(curve, rand.Reader)
		if err2 != nil {
			msg := fmt.Sprintf("could not generate key (%v)", err2)
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(msg))
			return
		}
		k.X = key.PublicKey.X.Bytes()
		k.Y = key.PublicKey.Y.Bytes()
		k.D = key.D.Bytes()
		err2 = srv.db.PutKey(ctx, k)
		if err2 != nil {
			msg := fmt.Sprintf("could not put key (%v)", err2)
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(msg))
			return
		}
	} else if err != nil {
		msg := fmt.Sprintf("could not load key (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	bs := k.publicKey()
	w.Write(bs)
}

func (srv *Server) putSubscription(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	u, err := srv.getUser(ctx)
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

	err = srv.db.PutSubscription(ctx, s, u)
	if err != nil {
		msg := fmt.Sprintf("could not save subscription (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}
}

func (srv *Server) getPosts(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	ps, err := srv.db.GetPosts(ctx)
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

func (srv *Server) putPost(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	u, err := srv.getUser(ctx)
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

	err = srv.db.PutPost(ctx, p)
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
	err = srv.tasks.Notify(ctx)
	if err != nil {
		log.Printf("could not notify clients: %v", err)
	}
}

func (srv *Server) getUser(ctx context.Context) (User, error) {
	ru := srv.auth.Current(ctx)

	u, err := srv.db.GetUser(ctx, ru.UUID)
	if err == ErrNoSuchEntity {
		err2 := srv.db.PutUser(ctx, u)
		if err2 != nil {
			return User{}, err2
		}
	} else if err != nil {
		return User{}, err
	}

	return u, nil
}

func (k KeyPair) publicKey() []byte {
	// uncompressed pubkey format
	bs := []byte{0x04}
	bs = append(bs, k.X...)
	bs = append(bs, k.Y...)
	return bs
}

func (srv *Server) notifyAll(ctx context.Context, _ string) error {
	// get server keys
	k, err := srv.db.GetKey(ctx)
	if err != nil {
		return fmt.Errorf("could not get server key: %v", err)
	}
	prvk := ecdsa.PrivateKey{
		PublicKey: ecdsa.PublicKey{
			Curve: curve,
			X:     new(big.Int),
			Y:     new(big.Int),
		},
		D: new(big.Int),
	}
	prvk.D.SetBytes(k.D)
	prvk.PublicKey.X.SetBytes(k.X)
	prvk.PublicKey.Y.SetBytes(k.Y)

	// get user keys
	ss, err := srv.db.GetSubscriptions(ctx)
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
			VAPIDPrivateKey: base64.RawURLEncoding.EncodeToString(prvk.D.Bytes()),
		})
		log.Printf("%v", res)
		if err != nil {
			log.Printf("could not send notification: %v", err)
		}
	}

	return nil
}
