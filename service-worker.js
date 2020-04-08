self.importScripts("/elm-worker.js");
self.importScripts("/elm-ports-indexeddb.js");
var app = Elm.Worker.init();
ElmPortsIndexedDB.bind(app);

// set up broadcast channel
const channel = new BroadcastChannel("sw-messages");
app.ports.sendBroadcast.subscribe(msg => {
    channel.postMessage(msg);
});
app.ports.fetchInternal.subscribe(() => {
    fetch("vapid-public-key")
        .then(response => {
            return response.text();
        })
        .then(function(text) {
            app.ports.onFetchResultInternal.send(text);
        });
});
app.ports.subscribeInternal.subscribe(pk => {
    self.registration.pushManager
        .subscribe({
            userVisibleOnly: true,
            applicationServerKey: pk
        })
        .then(subscription => {
            app.ports.sendSubscriptionState.send(subscription);
        });
});

var CACHE_NAME = "elm-pwa-example-cache-v1";
var urlsToCache = ["/", "/index.js", "/elm.js", "/base64ArrayBuffer.js"];
var db;

// set up database
var request = indexedDB.open("elm-pwa-example-db");
request.onerror = function(event) {
    alert("Why didn't you allow my web app to use IndexedDB?!");
};
request.onsuccess = function(event) {
    db = event.target.result;
};
request.onupgradeneeded = function(event) {
    var db = event.target.result;
    db.createObjectStore("posts", {
        keyPath: "id"
    });
};

self.addEventListener("install", function(event) {
    // Perform install steps
    event.waitUntil(
        caches.open(CACHE_NAME).then(function(cache) {
            return cache.addAll(urlsToCache);
        })
    );
});

self.addEventListener("activate", function(event) {
    // TODO try to create a Promise context in the SW-Elm
    event.waitUntil(
        self.clients.claim().then(
            self.registration.pushManager
                .getSubscription()
                .then(subscription => {
                    app.ports.sendSubscriptionState.send(subscription);
                })
        )
    );
});

self.addEventListener("fetch", function(event) {
    event.respondWith(
        caches.match(event.request).then(function(response) {
            // Cache hit - return response
            if (response) {
                return response;
            }
            return fetch(event.request);
        })
    );
});

self.addEventListener("sync", sync);

function sync() {
    var objectStore = db.transaction("posts").objectStore("posts");
    return adaptStoreToPromise(objectStore.getAll())
        .then(function(event) {
            var result = event.target.result;
            var toSync = result.filter(r => r.sync == "PENDING");
            console.log("read from db", toSync);
            return forEachPromise(toSync, syncPost);
        })
        .then(
            fetch("api/posts")
                .then(response => response.json())
                .then(function(posts) {
                    var transaction = db.transaction("posts", "readwrite");
                    var store = transaction.objectStore("posts");
                    return Promise.all(
                        posts.map(post => {
                            post["sync"] = "SYNCED";
                            return store.put(post);
                        })
                    )
                        .then(function() {
                            return transaction.complete;
                        })
                        .then(function() {
                            notifyClients();
                        });
                })
        );
}

self.addEventListener("push", function(event) {
    console.log("[Service Worker] Push Received.");

    var syncAndNotify = sync().then(notify());
    event.waitUntil(syncAndNotify);
});

function notify() {
    const title = "Push Codelab";
    const options = {
        body: "Yay it works."
    };
    self.registration.showNotification(title, options);
}

function adaptStoreToPromise(idbRequest) {
    return new Promise(function(resolve, reject) {
        idbRequest.onsuccess = function(event) {
            resolve(event);
        };
        idbRequest.onerror = function(event) {
            reject(event);
        };
    });
}

function syncPost(post) {
    return fetch("api/post", {
        method: "POST",
        headers: {
            "Content-Type": "application/json; charset=utf-8"
        },
        body: JSON.stringify(post)
    }).then(function(response) {
        response.json().then(function(json) {
            var deleteReq = db
                .transaction("posts", "readwrite")
                .objectStore("posts")
                .delete(post.id);
            deleteReq.onsuccess = function() {
                json["sync"] = "SYNCED";
                var insertReq = db
                    .transaction("posts", "readwrite")
                    .objectStore("posts")
                    .add(json);
                insertReq.onsuccess = notifyClients;
            };
        });
    });
}

function notifyClients() {
    self.clients.matchAll().then(clients => {
        clients.forEach(client => client.postMessage("update-db"));
    });
}

self.addEventListener("message", event => {
    app.ports.onMessageInternal.send(event.data);
});

function oldOnMessage(event) {
    var postsObjectStore = db
        .transaction("posts", "readwrite")
        .objectStore("posts");
    var post = event.data;
    post["sync"] = "PENDING";
    post["id"] = uuidv4();
    var request = postsObjectStore.add(post);
    request.onsuccess = function(event) {
        self.clients.matchAll().then(clients => {
            clients.forEach(client => client.postMessage("update-db"));
        });
        self.registration.sync.register("sync-posts");
    };
}
/**
 *
 * @param items An array of items.
 * @param fn A function that accepts an item from the array and returns a promise.
 * @returns {Promise}
 */
function forEachPromise(items, fn) {
    return items.reduce(function(promise, item) {
        return promise.then(function() {
            return fn(item);
        });
    }, Promise.resolve());
}

// https://stackoverflow.com/a/2117523/470509
function uuidv4() {
    return ([1e7] + -1e3 + -4e3 + -8e3 + -1e11).replace(/[018]/g, c =>
        (
            c ^
            (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))
        ).toString(16)
    );
}
