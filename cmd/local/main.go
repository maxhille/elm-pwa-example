package main

import (
	"context"
	"errors"
	"log"
	"net/http"

	"cloud.google.com/go/datastore"
	"github.com/google/uuid"
	"github.com/maxhille/elm-pwa-example/app"
	"google.golang.org/api/iterator"
)

func main() {
	db, err := newlocalDB()
	if err != nil {
		log.Fatal(err)
	}
	defer db.close()

	// for local dev
	http.Handle("/", LoggingHandler{http.FileServer(newPublicFileSystem())})

	app := app.New(
		db,
		newLocalUserService(db),
		&localHandler{},
	)

	if err := app.Run("8080"); err != nil {
		log.Fatal(err)
	}
}

type LoggingHandler struct {
	handler http.Handler
}

func (lh LoggingHandler) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	lrw := &loggingResponseWriter{rw: rw}
	lh.handler.ServeHTTP(lrw, req)
	log.Printf("%v %v %v", lrw.code, req.Method, req.URL)
}

type loggingResponseWriter struct {
	code int
	rw   http.ResponseWriter
}

func (lrw *loggingResponseWriter) Header() http.Header {
	return lrw.rw.Header()
}

func (lrw *loggingResponseWriter) Write(bs []byte) (int, error) {
	if lrw.code == 0 {
		lrw.code = 200
	}
	return lrw.rw.Write(bs)
}

func (lrw *loggingResponseWriter) WriteHeader(code int) {
	lrw.code = code
	lrw.rw.WriteHeader(code)
}

type publicFileSystem struct {
	base  http.Dir
	build http.Dir
}

func (fs *publicFileSystem) Open(name string) (http.File, error) {
	if name == "/elm.js" || name == "/elm-worker.js" {
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

type localHandler struct {
}

func (lh *localHandler) HandleFunc(pattern string,
	handler func(http.ResponseWriter, *http.Request)) {
	logHandler := func(rw http.ResponseWriter, req *http.Request) {
		lrw := &loggingResponseWriter{rw: rw}
		handler(lrw, req)
		log.Printf("%v %v %v", lrw.code, req.Method, req.URL)
	}
	http.HandleFunc(pattern, logHandler)
}

func (lh *localHandler) ListenAndServe(port string,
	handler http.Handler) error {
	log.Printf("app available at http://localhost%v", port)
	return http.ListenAndServe(port, handler)
}

type localDB struct {
	client *datastore.Client
}

func newlocalDB() (*localDB, error) {
	log.Printf("opening db")
	ctx := context.Background()
	cl, err := datastore.NewClient(ctx, "elm-pwa-example")
	if err != nil {
		return nil, err
	}

	return &localDB{cl}, nil
}

func (db *localDB) close() {
	db.client.Close()
}

func (db *localDB) GetKey(ctx context.Context) (app.KeyPair, error) {
	k := datastore.NameKey("VapidKey", "default", nil)
	kp := app.KeyPair{}
	err := db.client.Get(ctx, k, &kp)
	switch err {
	case datastore.ErrNoSuchEntity:
		return kp, app.ErrNoSuchEntity
	default:
		return kp, err
	}
}

func (db *localDB) PutKey(ctx context.Context, kp app.KeyPair) error {
	k := datastore.NameKey("VapidKey", "default", nil)
	_, err := db.client.Put(ctx, k, &kp)
	return err
}

func (db *localDB) GetUser(ctx context.Context, id uuid.UUID) (app.User, error) {
	uk := datastore.NameKey("User", id.String(), nil)
	u := app.User{}
	err := db.client.Get(ctx, uk, &u)
	u.ID = id
	return u, err
}

func (db *localDB) GetUsers(ctx context.Context) ([]app.User, error) {
	return nil, errors.New("not implemented")
}

func (db *localDB) PutUser(ctx context.Context, u app.User) error {
	uk := datastore.NameKey("User", u.ID.String(), nil)
	_, err := db.client.Put(ctx, uk, &u)
	return err
}

func (db *localDB) CreateSubscription(ctx context.Context, s app.Subscription) error {
	uk := datastore.NameKey("User", s.UserID.String(), nil)
	sk := datastore.NameKey("Subscription", "default", uk)
	_, err := db.client.Put(ctx, sk, &s)
	return err

}

func (db *localDB) ReadSubscription(ctx context.Context, uid uuid.UUID) (s app.Subscription, err error) {
	uk := datastore.NameKey("User", uid.String(), nil)
	sk := datastore.NameKey("Subscription", "default", uk)
	s.UserID = uid
	err = db.client.Get(ctx, sk, &s)
	if err == datastore.ErrNoSuchEntity {
		err = app.ErrNoSuchEntity
	}
	return
}

func (db *localDB) ReadAllSubscriptions(ctx context.Context) (ss []app.Subscription, err error) {
	q := datastore.NewQuery("Subscription")
	it := db.client.Run(ctx, q)
	for {
		var s app.Subscription
		_, err2 := it.Next(&s)
		if err2 == iterator.Done {
			break
		}
		if err2 != nil {
			return ss, err2
		}
		ss = append(ss, s)
	}

	return
}

func (db *localDB) ReadPosts(ctx context.Context) ([]app.Post, error) {
	return []app.Post{}, errors.New("not implemented")
}

func (db *localDB) PutPost(ctx context.Context, p app.Post) error {
	pk := datastore.NameKey("Post", p.ID.String(), nil)
	_, err := db.client.Put(ctx, pk, &p)
	return err
}

func (db *localDB) GetUserByName(ctx context.Context, name string) (u app.User, err error) {
	// TODO
	err = errors.New("not implemented")
	return
}

func newLocalUserService(db *localDB) app.UserService {
	return &localUserService{db: db}
}

type localUserService struct {
	db *localDB
}

func (us *localUserService) GetUserByName(ctx context.Context, name string) (app.User, error) {
	return app.User{}, errors.New("not implemented")
}

func (us *localUserService) Current(ctx context.Context) uuid.UUID {
	return ctx.Value("user").(uuid.UUID)
}

func (us *localUserService) Decorate(req *http.Request) (context.Context, error) {
	auth := req.Header["Authorization"]
	if len(auth) == 0 {
		return req.Context(), errors.New("authorization header missing")
	}
	id, err := uuid.Parse(auth[0])
	if err != nil {
		return req.Context(), err
	}
	return context.WithValue(req.Context(), "user", id), nil
}

func (us *localUserService) Login(ctx context.Context, name string) (uuid.UUID,
	error) {
	u, err := us.db.GetUserByName(ctx, name)
	return u.ID, err
}

func (us *localUserService) Register(ctx context.Context, name string) (app.User, error) {
	u := app.User{
		Name: name,
		ID:   uuid.New(),
	}
	return u, us.db.PutUser(ctx, u)
}
