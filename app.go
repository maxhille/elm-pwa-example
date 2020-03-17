package main

import (
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

	"golang.org/x/net/context"

	webpush "github.com/SherClockHolmes/webpush-go"
	"google.golang.org/appengine"
	"google.golang.org/appengine/datastore"
	"google.golang.org/appengine/delay"
	guser "google.golang.org/appengine/user"
)

func main() {
	// port := os.Getenv("PORT")
	// if port == "" {
	//   port = "8080"
	//   fmt.Printf("Defaulting to port %s", port)
	// }

	// fmt.Printf("Listening on port %s", port)
	// http.ListenAndServe(fmt.Sprintf(":%s", port), nil)
	appengine.Main()
}

func init() {
	http.HandleFunc("/vapid-public-key", getPublicKey)
	http.HandleFunc("/api/subscription", putSubscription)
	http.HandleFunc("/api/post", putPost)
	http.HandleFunc("/api/posts", getPosts)
}

var curve = elliptic.P256()

type subscription struct {
	Endpoint string `json:"endpoint"`
	P256dh   []byte `json:"p256dh"`
	Auth     []byte `json:"auth"`
}

type post struct {
	Id     string    `json:"id" datastore:"-"`
	Author string    `json:"author"`
	Text   string    `json:"text"`
	Time   time.Time `json:"time"`
}

type keyPair struct {
	X []byte
	Y []byte
	D []byte
}

type user struct {
	Key   *datastore.Key
	Email string
	Name  string
}

var task = delay.Func("notify-all", notifyAll)

func getPublicKey(w http.ResponseWriter, req *http.Request) {
	ctx := appengine.NewContext(req)

	kk := datastore.NewKey(ctx, "KeyPair", "vapid-keypair", 0, nil)
	k := keyPair{}
	err := datastore.Get(ctx, kk, &k)

	// no key yet? let's build it now
	if err == datastore.ErrNoSuchEntity {
		key, err2 := ecdsa.GenerateKey(curve, rand.Reader)
		if err2 != nil {
			msg := fmt.Sprintf("could not generate key (%v)", err2)
			w.Write([]byte(msg))
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		k.X = key.PublicKey.X.Bytes()
		k.Y = key.PublicKey.Y.Bytes()
		k.D = key.D.Bytes()
		_, err2 = datastore.Put(ctx, kk, &k)
		if err2 != nil {
			msg := fmt.Sprintf("could not put key (%v)", err2)
			w.Write([]byte(msg))
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
	} else if err != nil {
		msg := fmt.Sprintf("could not load key (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	bs := k.publicKey()
	w.Write(bs)
}

func putSubscription(w http.ResponseWriter, req *http.Request) {
	ctx := appengine.NewContext(req)
	u, err := getUser(ctx)
	if err != nil {
		msg := fmt.Sprintf("could not get user (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	decoder := json.NewDecoder(req.Body)
	s := subscription{}
	err = decoder.Decode(&s)
	if err != nil {
		msg := fmt.Sprintf("could not read json body key (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	// TODO make this idempotent. either check for existence or use auth/p256dh as key
	sk := datastore.NewIncompleteKey(ctx, "Subscription", u.Key)
	_, err = datastore.Put(ctx, sk, &s)
	if err != nil {
		msg := fmt.Sprintf("could not save subscription (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
}

func getPosts(w http.ResponseWriter, req *http.Request) {
	ctx := appengine.NewContext(req)
	ps := []post{}
	pks, err := datastore.NewQuery("Post").
		GetAll(ctx, &ps)
	if err != nil {
		msg := fmt.Sprintf("could not get posts from db: %v", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	for i, _ := range ps {
		ps[i].Id = pks[i].Encode()
	}

	json, err := json.Marshal(&ps)
	if err != nil {
		msg := fmt.Sprintf("could not marshal posts (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
	w.Write(json)
}

func putPost(w http.ResponseWriter, req *http.Request) {
	ctx := appengine.NewContext(req)
	u, err := getUser(ctx)
	if err != nil {
		msg := fmt.Sprintf("could not get user (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	decoder := json.NewDecoder(req.Body)
	p := post{
		Author: u.Name,
		Time:   time.Now(),
	}
	err = decoder.Decode(&p)
	if err != nil {
		msg := fmt.Sprintf("could not read json body key (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	pik := datastore.NewIncompleteKey(ctx, "Post", nil)
	pk, err := datastore.Put(ctx, pik, &p)
	if err != nil {
		msg := fmt.Sprintf("could not save post (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	p.Id = pk.Encode()

	json, err := json.Marshal(&p)
	if err != nil {
		msg := fmt.Sprintf("could not marshal post (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.Write(json)
	w.WriteHeader(http.StatusCreated)

	// send push
	task.Call(ctx, "")
}

func getUser(ctx context.Context) (*user, error) {
	gu := guser.Current(ctx)

	uk := datastore.NewKey(ctx, "User", gu.Email, 0, nil)
	u := user{}
	err := datastore.Get(ctx, uk, &u)
	if err == datastore.ErrNoSuchEntity {
		u.Email = gu.Email
		u.Key = uk
		u.Name = gu.String()
		_, err2 := datastore.Put(ctx, uk, &u)
		if err2 != nil {
			return nil, err2
		}
	} else if err != nil {
		return nil, err
	}

	return &u, nil
}

func (k keyPair) publicKey() []byte {
	// uncompressed pubkey format
	bs := []byte{0x04}
	bs = append(bs, k.X...)
	bs = append(bs, k.Y...)
	return bs
}

func sendTestMessageTo(ctx context.Context, ep string, auth []byte, p256dh []byte) {

	kk := datastore.NewKey(ctx, "KeyPair", "vapid-keypair", 0, nil)
	k := keyPair{}
	_ = datastore.Get(ctx, kk, &k)
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

	s := webpush.Subscription{}
	s.Endpoint = ep
	s.Keys = webpush.Keys{}
	s.Keys.Auth = base64.RawURLEncoding.EncodeToString(auth)
	s.Keys.P256dh = base64.RawURLEncoding.EncodeToString(p256dh)

	// Send Notification
	_, err := webpush.SendNotification([]byte("TestXYZ"), &s, &webpush.Options{
		Subscriber:      "<mh@lambdasoup.com>",
		VAPIDPrivateKey: base64.RawURLEncoding.EncodeToString(prvk.D.Bytes()),
	})
	if err != nil {
		log.Printf("could not send notification: %v", err)
	}
}

func notifyAll(ctx context.Context, _ string) error {
	uks, err := datastore.NewQuery("User").
		KeysOnly().
		GetAll(ctx, nil)
	if err != nil {
		log.Printf("could not notify users: %v", err)
		return err
	}

	for _, uk := range uks {
		err = notify(ctx, uk)
		if err != nil {
			log.Printf("could not notify user %v: %v", uk, err)
		}
	}
	return nil
}

// Notify sends the given message to the given user
func notify(ctx context.Context, uk *datastore.Key) error {
	// get server keys
	kk := datastore.NewKey(ctx, "KeyPair", "vapid-keypair", 0, nil)
	k := keyPair{}
	_ = datastore.Get(ctx, kk, &k)
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
	ss := []subscription{}
	_, err := datastore.NewQuery("Subscription").Ancestor(uk).GetAll(ctx, &ss)
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
