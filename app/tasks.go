package app

import "context"

type Tasks interface {
	Notify(context.Context) error
}
