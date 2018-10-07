var CACHE_NAME = 'elm-pwa-example-cache-v1';
var urlsToCache = [
  '/',
  '/index.js',
  '/elm.js',
  '/base64ArrayBuffer.js',
  '/vapid-public-key',
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
    autoIncrement: true
  });
};

self.addEventListener('install', function(event) {
  // Perform install steps
  event.waitUntil(
    caches.open(CACHE_NAME)
    .then(function(cache) {
      console.log('Opened cache');
      return cache.addAll(urlsToCache);
    })
  );
});

self.addEventListener('fetch', function(event) {
  event.respondWith(
    caches.match(event.request)
    .then(function(response) {
      // Cache hit - return response
      if (response) {
        return response;
      }
      return fetch(event.request);
    })
  );
});

self.addEventListener('sync', function(event) {
  console.log("sync");
  return readPosts()
});

function readPosts() {
  var objectStore = db.transaction("posts").objectStore("posts");
  return adaptStoreToPromise(objectStore.getAll()).then(function(event) {
    var result = event.target.result;
    var toSync = result.filter(r => r.sync == "PENDING");
    console.log("read from db", toSync);
    return forEachPromise(toSync, syncPost)
  });
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
  console.log("posting", post);
  return fetch("posts", {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify(post),
  });
}

self.addEventListener('message', function(event) {
  var postsObjectStore = db.transaction("posts", "readwrite").objectStore(
    "posts");
  var post = event.data;
  post["sync"] = "PENDING"
  var request = postsObjectStore.add(post);
  request.onsuccess = function(event) {
    self.clients.matchAll().then(clients => {
      clients.forEach(client => client.postMessage("update-db"));
    });
    self.registration.sync.register("sync-posts")
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
