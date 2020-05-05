self.importScripts("/elm-worker.js");
self.importScripts("/elm-ports-indexeddb.js");
var app = Elm.Worker.init();
ElmPortsIndexedDB.bind(app);

// set up broadcast channel
const channel = new BroadcastChannel("sw-messages");
app.ports.postMessageInternal.subscribe(msg => {
    channel.postMessage(msg);
});

app.ports.getVapidKey.subscribe(() => {
    fetch("vapid-public-key")
        .then(response => {
            return response.text();
        })
        .then(function(text) {
            app.ports.onVapidkeyResult.send(text);
        });
});
app.ports.sendLogin.subscribe(opts => {
    fetch("/api/login", {
        method: "POST",
        body: JSON.stringify(opts)
    })
        .then(response => {
            return response.json();
        })
        .then(function(json) {
            app.ports.onLoginResult.send(json);
        });
});

app.ports.subscribeInternal.subscribe(key => {
    var options = {
        userVisibleOnly: true,
        applicationServerKey: key
    };
    registration.pushManager
        .subscribe(options)
        .then(subscription => {
            app.ports.onNewSubscriptionInternal.send(subscription.toJSON());
        })
        .catch(x => {
            console.log(x);
        });
});

app.ports.uploadSubscription.subscribe(opts => {
    fetch("/api/subscription", {
        method: "POST",
        headers: new Headers({
            Authorization: opts.auth,
            "Content-Type": "application/json"
        }),
        body: JSON.stringify({
            endpoint: opts.payload.endpoint,
            auth: btoa(opts.payload.auth),
            p256dh: btoa(opts.payload.p256dh)
        })
    }).then(response => {
        var result = response.status == 201;
        app.ports.getSubscriptionReply.send(result);
    });
});

app.ports.uploadPosts.subscribe(opts => {
    fetch("/api/posts", {
        method: "POST",
        headers: new Headers({
            Authorization: opts.auth,
            "Content-Type": "application/json"
        }),
        body: JSON.stringify(opts.payload)
    }).then(response => {
        var result = response.status == 201;
        app.ports.uploadPostsReply.send(result);
    });
});

app.ports.getSubscription.subscribe(opts => {
    fetch("/api/subscription", {
        headers: new Headers({
            Authorization: opts.auth
        })
    }).then(response => {
        var result = response.status == 204;
        app.ports.getSubscriptionReply.send(result);
    });
});

self.navigator.permissions.query({ name: "notifications" }).then(ps => {
    app.ports.onPermissionChangeInternal.send(ps.state);
    ps.onchange = ev => {
        console.log(ev.target);
        app.ports.onPermissionChangeInternal.send(ev.target.state);
    };
});

var CACHE_NAME = "elm-pwa-example-cache-v1";
var urlsToCache = [
    "/",
    "/index.js",
    "/elm.js",
    "/elm-worker.js",
    "/vapid-public-key"
];

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
    event.waitUntil(self.clients.claim());
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

self.addEventListener("sync", event => {
    app.ports.onSync.send();
});

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

self.addEventListener("message", event => {
    app.ports.onMessageInternal.send(event.data);
});
