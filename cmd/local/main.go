package main

import (
	"context"
	"log"
	"net/http"

	"github.com/google/uuid"
	"github.com/maxhille/elm-pwa-example/app"
)

func main() {
	// for local dev
	http.Handle("/", LoggingHandler{http.FileServer(newPublicFileSystem())})

	db := &LocalDB{
		keyPair: &app.KeyPair{
			PK: "BDRhEg7bDxxreAwuUgr2zzwx7_CzYZR1xr8Q2xIVJD8o8ida48HjWrZPLk1_QSw9aDzjtMf0vDvaBEQYaFmqGdo",
			SK: "uIzZugiNNxVTW24JheKfCJ6fHwtKBGSPTCek-QOupjo",
		},
	}

	app := app.New(
		db,
		&LocalTasks{},
		&LocalAuth{},
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
	keyPair *app.KeyPair
}

func (db *LocalDB) GetKey(ctx context.Context) (app.KeyPair, error) {
	if db.keyPair == nil {
		return app.KeyPair{}, app.ErrNoSuchEntity
	}
	return *db.keyPair, nil
}

func (db *LocalDB) PutKey(ctx context.Context, k app.KeyPair) error {
	log.Printf("saving new keypair: %v", k)
	db.keyPair = &k
	return nil
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

type LocalTasks struct {
	app.Tasks
}

func (ct *LocalTasks) Notify(ctx context.Context) error {
	// TODO notify
	return nil
}

type LocalAuth struct {
	app.Auth
}

func (ga *LocalAuth) Current(ctx context.Context) app.User {
	// TODO migrate somewhere new, was
	//	return guser.Current(ctx)
	return app.User{}
}
