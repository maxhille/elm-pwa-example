package app

import "net/http"

func init() {
	http.HandleFunc("/vapid-public-key", getPublicKey)
	http.HandleFunc("/subscription", putSubscription)
}
