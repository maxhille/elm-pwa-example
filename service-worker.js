var CACHE_NAME = "elm-pwa-example-cache-v1";
var urlsToCache = [
  "/",
  "/index.js",
  "/elm.js",
  "/base64ArrayBuffer.js",
  "/vapid-public-key"
];
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
      console.log("Opened cache");
      return cache.addAll(urlsToCache);
    })
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

self.addEventListener("sync", function(event) {
  var objectStore = db.transaction("posts").objectStore("posts");
  return adaptStoreToPromise(objectStore.getAll()).then(function(event) {
    var result = event.target.result;
    var toSync = result.filter(r => r.sync == "PENDING");
    console.log("read from db", toSync);
    return forEachPromise(toSync, syncPost);
  });
});

self.addEventListener("push", function(event) {
  console.log("[Service Worker] Push Received.");

  const title = "Push Codelab";
  const options = {
    body: "Yay it works."
  };
  var syncAndNotify = sync.then(notify)

  event.waitUntil(self.registration.showNotification(title, options));
});

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
  console.log("posting", post);
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
        insertReq.onsuccess = function() {
          self.clients.matchAll().then(clients => {
            clients.forEach(client => client.postMessage("update-db"));
          });
        };
      };
    });
  });
}

self.addEventListener("message", function(event) {
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
});

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
