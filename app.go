package app

import "net/http"

func init() {
	http.HandleFunc("/vapid-public-key", getVapidPublicKey)
}

func getVapidPublicKey(w http.ResponseWriter, r *http.Request) {
	return
}
