package app

import "net/http"

func init() {
	http.HandleFunc("/vapid-public-key", GetPublicKey)
}
