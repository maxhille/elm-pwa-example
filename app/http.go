package app

import "net/http"

type HttpHandler interface {
	HandleFunc(string, func(http.ResponseWriter, *http.Request))
	ListenAndServe(string, http.Handler) error
}
