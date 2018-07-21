var CACHE_NAME = 'elm-pwa-example-cache-v1';
var urlsToCache = [
  '/',
  '/index.js'
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
  db.createObjectStore("posts", { autoIncrement: true });
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

self.addEventListener('message', function(event){
  var postsObjectStore = db.transaction("posts", "readwrite").objectStore("posts");
  var request = postsObjectStore.add(event.data);
  request.onsuccess = function(event) {
    self.clients.matchAll().then(clients => {
      clients.forEach(client => client.postMessage("update-db"));
    });
  };
});
