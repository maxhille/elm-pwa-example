package app

import "context"

type NameToken struct {
	Name  string `json:"name"`
	Token string `json:"token"`
}

type Auth interface {
	Current(context.Context) User
	Login(context.Context, string) (*NameToken, error)
}
