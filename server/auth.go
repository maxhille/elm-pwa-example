package server

import "context"

type Auth interface {
	Current(context.Context) User
}
