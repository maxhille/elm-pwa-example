package main

import (
	"context"
	"log"
	"net/http"

	"github.com/google/uuid"
	"github.com/maxhille/elm-pwa-example/server"
)

func main() {
	// for local dev
	http.Handle("/", LoggingHandler{http.FileServer(newPublicFileSystem())})

	srv := server.New(
		&LocalDB{},
		&LocalTasks{},
		&LocalAuth{},
		&LocalHandler{},
	)

	if err := srv.Run("8080"); err != nil {
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
	server.DB
}

func (db *LocalDB) GetUser(ctx context.Context, id uuid.UUID) (server.User,
	error) {
	// TODO implement
	return server.User{}, nil
}

func (db *LocalDB) PutUser(ctx context.Context, u server.User) error {
	// TODO implement
	return nil
}
func (db *LocalDB) PutSubscription(ctx context.Context, s server.Subscription,
	u server.User) error {
	// TODO implement
	return nil
}

func (db *LocalDB) GetSubscriptions(ctx context.Context) ([]server.Subscription,
	error) {
	// TODO implement
	return []server.Subscription{}, nil
}

func (db *LocalDB) GetPublicKey(ctx context.Context) (server.KeyPair, error) {
	// TODO implement
	return server.KeyPair{}, nil
}

func (db *LocalDB) GetPosts(ctx context.Context) ([]server.Post, error) {
	// TODO implement
	return []server.Post{}, nil
}

func (db *LocalDB) PutPost(ctx context.Context, p server.Post) error {
	// TODO implement
	return nil
}

type LocalTasks struct {
	server.Tasks
}

func (ct *LocalTasks) Notify(ctx context.Context) error {
	// TODO notify
	return nil
}

type LocalAuth struct {
	server.Auth
}

func (ga *LocalAuth) Current(ctx context.Context) server.User {
	// TODO migrate somewhere new, was
	//	return guser.Current(ctx)
	return server.User{}
}
