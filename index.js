var db;

function postAndClear() {
  var el = document.getElementById("new-post-text");
  var text = el.value;
  el.value = "";
  var post = {
    text: text,
    me: true,
    author: null
  };
  navigator.serviceWorker.controller.postMessage(post);
}

function refreshPosts() {
  var objectStore = db.transaction("posts").objectStore("posts");

  var ul = document.getElementById("posts");
  while (ul.firstChild) {
    ul.removeChild(ul.firstChild);
  }

  objectStore.openCursor().onsuccess = function(event) {
    var cursor = event.target.result;
    if (cursor) {
      var text = cursor.value.text;
      var li = document.createElement("li");
      var te = document.createTextNode(text);
      li.appendChild(te);
      ul.appendChild(li);
      cursor.continue();
    }
  };
}

function init() {
  // set up service worker
  if (!('serviceWorker' in navigator)) {
    alert("Your browser does not support Service Workers - please use a proper browser!");
    return;
  }
  navigator.serviceWorker.onmessage = function(event) {
    refreshPosts();
  }
  navigator.serviceWorker.register('/service-worker.js')
    .then(function(registration) {},
          function(err) { alert("Could not register Service Worker :-(") ;});

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
