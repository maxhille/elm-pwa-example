package app

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"

	"golang.org/x/net/context"

	webpush "github.com/SherClockHolmes/webpush-go"
	"google.golang.org/appengine"
	"google.golang.org/appengine/datastore"
	"google.golang.org/appengine/delay"
	"google.golang.org/appengine/log"
	"google.golang.org/appengine/urlfetch"
	guser "google.golang.org/appengine/user"
)

func init() {
	http.HandleFunc("/vapid-public-key", getPublicKey)
	http.HandleFunc("/api/subscription", putSubscription)
	http.HandleFunc("/api/post", putPost)
}

var curve = elliptic.P256()

type subscription struct {
	Endpoint string `json:"endpoint"`
	P256dh   []byte `json:"p256dh"`
	Auth     []byte `json:"auth"`
}

type post struct {
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

	sk := datastore.NewIncompleteKey(ctx, "Subscription", u.Key)
	_, err = datastore.Put(ctx, sk, &s)
	if err != nil {
		msg := fmt.Sprintf("could not save subscription (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
}

func putPost(w http.ResponseWriter, req *http.Request) {
	ctx := appengine.NewContext(req)
	_, err := getUser(ctx)
	if err != nil {
		msg := fmt.Sprintf("could not get user (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	decoder := json.NewDecoder(req.Body)
	p := post{}
	err = decoder.Decode(&p)
	if err != nil {
		msg := fmt.Sprintf("could not read json body key (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	ck := datastore.NewKey(ctx, "Channel", "channel-1", 0, nil)
	pk := datastore.NewIncompleteKey(ctx, "Post", ck)
	_, err = datastore.Put(ctx, pk, &p)
	if err != nil {
		msg := fmt.Sprintf("could not save post (%v)", err)
		w.Write([]byte(msg))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
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
		HTTPClient:      urlfetch.Client(ctx),
	})
	if err != nil {
		log.Errorf(ctx, "could not send notification: %v", err)
	}
}

func notifyAll(ctx context.Context, _ string) error {
	uks, err := datastore.NewQuery("User").
		KeysOnly().
		GetAll(ctx, nil)
	if err != nil {
		log.Errorf(ctx, "could not notify users: %v", err)
		return err
	}

	for _, uk := range uks {
		err = notify(ctx, uk)
		if err != nil {
			log.Errorf(ctx, "could not notify user %v: %v", uk, err)
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

	log.Infof(ctx, "notifying %d users", len(ss))

	// send pushes to each sub
	for _, s := range ss {
		ws := webpush.Subscription{}
		ws.Endpoint = s.Endpoint
		ws.Keys = webpush.Keys{}
		ws.Keys.Auth = base64.RawURLEncoding.EncodeToString(s.Auth)
		ws.Keys.P256dh = base64.RawURLEncoding.EncodeToString(s.P256dh)

		// Send Notification
		_, err = webpush.SendNotification([]byte("msg-sync"), &ws, &webpush.Options{
			Subscriber:      "<mh@lambdasoup.com>",
			VAPIDPrivateKey: base64.RawURLEncoding.EncodeToString(prvk.D.Bytes()),
			HTTPClient:      urlfetch.Client(ctx),
		})
		if err != nil {
			log.Warningf(ctx, "could not send notification: %v", err)
		}
	}

	return nil
}
