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
	"os"
	"time"

	"golang.org/x/net/context"

	cloudtasks "cloud.google.com/go/cloudtasks/apiv2beta3"
	"cloud.google.com/go/datastore"
	webpush "github.com/SherClockHolmes/webpush-go"
	guser "google.golang.org/appengine/user"
	taskspb "google.golang.org/genproto/googleapis/cloud/tasks/v2beta3"
)

func main() {
	// for local dev, should be overridden by appengine file serving
	http.Handle("/", http.FileServer(newPublicFileSystem()))

	http.HandleFunc("/vapid-public-key", getPublicKey)
	http.HandleFunc("/api/subscription", putSubscription)
	http.HandleFunc("/api/post", putPost)
	http.HandleFunc("/api/posts", getPosts)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
		log.Printf("Defaulting to port %s", port)
	}

	log.Printf("Listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
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

func getPublicKey(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		msg := fmt.Sprintf("could not create datastore client (%v)", err)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(msg))
		return
	}

	kk := datastore.NameKey("KeyPair", "vapid-keypair", nil)
	k := keyPair{}
	err = dsc.Get(ctx, kk, &k)

	// no key yet? let's build it now
	if err == datastore.ErrNoSuchEntity {
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
		_, err2 = dsc.Put(ctx, kk, &k)
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

func putSubscription(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		msg := fmt.Sprintf("could not create datastore client (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

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
	sk := datastore.IncompleteKey("Subscription", u.Key)
	_, err = dsc.Put(ctx, sk, &s)
	if err != nil {
		msg := fmt.Sprintf("could not save subscription (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
}

func getPosts(w http.ResponseWriter, req *http.Request) {
	ctx := req.Context()

	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		msg := fmt.Sprintf("could not create datastore client (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	ps := []post{}
	q := datastore.NewQuery("Post")
	pks, err := dsc.GetAll(ctx, q, &ps)
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
	ctx := req.Context()

	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		msg := fmt.Sprintf("could not create datastore client (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	ctc, err := cloudtasks.NewClient(ctx)
	if err != nil {
		msg := fmt.Sprintf("could not create cloud tasks client (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

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

	pik := datastore.IncompleteKey("Post", nil)
	pk, err := dsc.Put(ctx, pik, &p)
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
	treq := &taskspb.CreateTaskRequest{
		// TODO complete, was
		// delay.Func("notify-all", notifyAll)
	}
	_, _ = ctc.CreateTask(ctx, treq)
}

func getUser(ctx context.Context) (*user, error) {
	gu := guser.Current(ctx)

	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		return nil, fmt.Errorf("could not create datastore client (%v)", err)
	}

	uk := datastore.NameKey("User", gu.Email, nil)
	u := user{}
	err = dsc.Get(ctx, uk, &u)
	if err == datastore.ErrNoSuchEntity {
		u.Email = gu.Email
		u.Key = uk
		u.Name = gu.String()
		_, err2 := dsc.Put(ctx, uk, &u)
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
	dsc, _ := datastore.NewClient(ctx, "my-project")

	kk := datastore.NameKey("KeyPair", "vapid-keypair", nil)
	k := keyPair{}
	_ = dsc.Get(ctx, kk, &k)
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
	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		return fmt.Errorf("could not create datastore client (%v)", err)
	}

	q := datastore.NewQuery("User").
		KeysOnly()
	uks, err := dsc.GetAll(ctx, q, nil)
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
	dsc, err := datastore.NewClient(ctx, "my-project")
	if err != nil {
		return fmt.Errorf("could not create datastore client (%v)", err)
	}

	// get server keys
	kk := datastore.NameKey("KeyPair", "vapid-keypair", nil)
	k := keyPair{}
	_ = dsc.Get(ctx, kk, &k)
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
	q := datastore.NewQuery("Subscription").Ancestor(uk)
	_, err = dsc.GetAll(ctx, q, &ss)
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
