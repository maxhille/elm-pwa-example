package app

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

var (
	ErrNoSuchEntity = errors.New("Not such entity in database")
)

type DB interface {
	GetUser(context.Context, uuid.UUID) (User, error)
	GetUsers(context.Context) ([]User, error)
	PutUser(context.Context, User) error
	PutSubscription(context.Context, Subscription, User) error
	GetSubscriptions(context.Context) ([]Subscription, error)
	GetKey(context.Context) (*KeyPair, error)
	PutKey(context.Context, *KeyPair) error
	GetPosts(context.Context) ([]Post, error)
	PutPost(context.Context, Post) error
}
