var db;

function post(text) {
  var post = {
    text: text,
    me: true,
    author: null
  };
  navigator.serviceWorker.controller.postMessage(post);
}

function refreshPosts() {
  var objectStore = db.transaction("posts").objectStore("posts");

  objectStore.getAll().onsuccess = function(event) {
    var result = event.target.result;
    app.ports.updatePosts.send(result);
  };
}

function init() {
  // set up service worker
  if (!("serviceWorker" in navigator)) {
    alert(
      "Your browser does not support Service Workers - please use a proper browser!"
    );
    return;
  }
  navigator.serviceWorker.onmessage = function(event) {
    refreshPosts();
  };
  navigator.serviceWorker.register("/service-worker.js").then(
    function(registration) {},
    function(err) {
      alert("Could not register Service Worker :-(");
    }
  );

  // set up database
  var request = indexedDB.open("elm-pwa-example-db");
  request.onerror = function(event) {
    alert("Why didn't you allow my web app to use IndexedDB?!");
  };
  request.onsuccess = function(event) {
    db = event.target.result;
    refreshPosts();
  };
  request.onupgradeneeded = function(event) {
    var db = event.target.result;
    db.createObjectStore("posts", { autoIncrement: true });
  };
}
