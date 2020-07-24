package app

import (
	"context"
	"net/http"

	"github.com/google/uuid"
)

type User struct {
	ID   uuid.UUID `json:"id" datastore:"-"`
	Name string    `json:"name"`
}

type UserService interface {
	Current(context.Context) uuid.UUID
	Decorate(*http.Request) (context.Context, error)
	Register(context.Context, string) (User, error)
	Login(context.Context, string) (uuid.UUID, error)
	GetUserByName(context.Context, string) (User, error)
}
