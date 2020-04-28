package main

import (
	"context"
	"errors"
	"log"
	"net/http"

	"github.com/google/uuid"
	"github.com/jinzhu/gorm"
	_ "github.com/jinzhu/gorm/dialects/sqlite"
	"github.com/maxhille/elm-pwa-example/app"
)

type Account struct {
	Name  string
	Token string
}

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
		&localTasks{},
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
	gorm *gorm.DB
}

func newlocalDB() (*localDB, error) {
	db, err := gorm.Open("sqlite3", ".local.db")
	if err != nil {
		return nil, err
	}

	db.AutoMigrate(&app.KeyPair{})
	db.AutoMigrate(&app.Subscription{})
	db.AutoMigrate(&app.User{})

	return &localDB{db}, nil
}

func (db *localDB) close() {
	db.gorm.Close()
}

func (db *localDB) GetKey(ctx context.Context) (app.KeyPair, error) {
	kp := app.KeyPair{}
	err := db.gorm.Take(&kp).Error
	if err != nil {
		log.Printf("getkey err: %v", err)
		return kp, app.ErrNoSuchEntity
	}
	return kp, nil
}

func (db *localDB) PutKey(ctx context.Context, kp app.KeyPair) error {
	log.Printf("saving new keypair: %v", kp)
	db.gorm.Create(&kp)
	return nil
}

func (db *localDB) GetUser(ctx context.Context, id uuid.UUID) (app.User,
	error) {
	return app.User{}, errors.New("not implemented")
}

func (db *localDB) GetUsers(ctx context.Context) ([]app.User,
	error) {
	return nil, errors.New("not implemented")
}

func (db *localDB) PutUser(ctx context.Context, u app.User) error {
	return errors.New("not implemented")
}

func (db *localDB) PutSubscription(ctx context.Context, s app.Subscription,
	u app.User) error {
	return errors.New("not implemented")
}

func (db *localDB) GetSubscriptions(ctx context.Context) ([]app.Subscription,
	error) {
	return []app.Subscription{}, errors.New("not implemented")
}

func (db *localDB) GetPosts(ctx context.Context) ([]app.Post, error) {
	return []app.Post{}, errors.New("not implemented")
}

func (db *localDB) PutPost(ctx context.Context, p app.Post) error {
	return errors.New("not implemented")
}

func (db *localDB) GetUserByName(ctx context.Context, name string) (u app.User,
	err error) {
	err = db.gorm.First(&u).Error
	return
}
func (db *localDB) createUser(u *app.User) error {
	return db.gorm.Create(&u).Error
}

type localTasks struct {
	app.Tasks
}

func (ct *localTasks) Notify(ctx context.Context) error {
	// TODO notify
	return nil
}

func newLocalUserService(db *localDB) app.UserService {
	return &localUserService{db: db}
}

type localUserService struct {
	db *localDB
}

func (us *localUserService) GetUserByName(ctx context.Context, name string) (
	app.User, error) {
	return app.User{}, errors.New("not implemented")
}

func (us *localUserService) Current(ctx context.Context) uuid.UUID {
	return ctx.Value("user").(uuid.UUID)
}

func (us *localUserService) Decorate(req *http.Request) (context.Context, error) {
	auth := req.Header["Authorization"]
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

func (us *localUserService) Register(ctx context.Context, name string) (
	app.User, error) {
	u := app.User{
		Name: name,
		ID:   uuid.New(),
	}
	return u, us.db.createUser(&u)
}
