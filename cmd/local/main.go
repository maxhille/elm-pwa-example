package main

import (
	"context"
	"log"
	"net/http"

	"github.com/asdine/storm/v3"
	"github.com/google/uuid"
	"github.com/maxhille/elm-pwa-example/app"
)

func main() {
	// for local dev
	http.Handle("/", LoggingHandler{http.FileServer(newPublicFileSystem())})

	db, _ := newLocalDB()
	defer db.close()
	app := app.New(
		db,
		&LocalTasks{},
		&LocalAuth{db},
		&LocalHandler{},
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

type LocalHandler struct {
}

func (lh *LocalHandler) HandleFunc(pattern string,
	handler func(http.ResponseWriter, *http.Request)) {
	logHandler := func(rw http.ResponseWriter, req *http.Request) {
		lrw := &loggingResponseWriter{rw: rw}
		handler(lrw, req)
		log.Printf("%v %v %v", lrw.code, req.Method, req.URL)
	}
	http.HandleFunc(pattern, logHandler)
}

func (lh *LocalHandler) ListenAndServe(port string,
	handler http.Handler) error {
	log.Printf("app available at http://localhost%v", port)
	return http.ListenAndServe(port, handler)
}

type LocalDB struct {
	db *storm.DB
}

func newLocalDB() (*LocalDB, error) {
	db, err := storm.Open(".storm.db")
	if err != nil {
		return nil, err
	}
	return &LocalDB{db}, nil
}

func (db *LocalDB) close() {
	db.db.Close()
}

func (db *LocalDB) GetKey(ctx context.Context) (*app.KeyPair, error) {
	kp := app.KeyPair{}
	err := db.db.Get("keypair", 0, &kp)
	if err != nil {
		return nil, app.ErrNoSuchEntity
	}
	return &kp, nil
}

func (db *LocalDB) PutKey(ctx context.Context, kp *app.KeyPair) error {
	log.Printf("saving new keypair: %v", kp)
	return db.db.Set("keypair", 0, kp)
}

func (db *LocalDB) GetUser(ctx context.Context, id uuid.UUID) (app.User,
	error) {
	// TODO implement
	return app.User{}, nil
}

func (db *LocalDB) GetUsers(ctx context.Context) ([]app.User,
	error) {
	// TODO implement
	return nil, nil
}
func (db *LocalDB) PutUser(ctx context.Context, u app.User) error {
	// TODO implement
	return nil
}
func (db *LocalDB) PutSubscription(ctx context.Context, s app.Subscription,
	u app.User) error {
	// TODO implement
	return nil
}

func (db *LocalDB) GetSubscriptions(ctx context.Context) ([]app.Subscription,
	error) {
	// TODO implement
	return []app.Subscription{}, nil
}

func (db *LocalDB) GetPublicKey(ctx context.Context) (app.KeyPair, error) {
	// TODO implement
	return app.KeyPair{}, nil
}

func (db *LocalDB) GetPosts(ctx context.Context) ([]app.Post, error) {
	// TODO implement
	return []app.Post{}, nil
}

func (db *LocalDB) PutPost(ctx context.Context, p app.Post) error {
	// TODO implement
	return nil
}

func (db *LocalDB) saveLogin(name string, token string) error {
	return db.db.Set("logins", token, name)
}

type LocalTasks struct {
	app.Tasks
}

func (ct *LocalTasks) Notify(ctx context.Context) error {
	// TODO notify
	return nil
}

type LocalAuth struct {
	db *LocalDB
}

func (ga *LocalAuth) Current(ctx context.Context) app.User {
	// TODO migrate somewhere new, was
	//	return guser.Current(ctx)
	return app.User{}
}

func (la *LocalAuth) Login(ctx context.Context, name string) (*app.NameToken,
	error) {
	err := la.db.saveLogin(name, "dummy-token")
	return &app.NameToken{Name: name, Token: "dummy-token"}, err
}
