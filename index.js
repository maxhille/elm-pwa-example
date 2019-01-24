var db;

function post(text) {
  var post = {
    text: text,
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
    db.createObjectStore("posts", {
      keyPath: "id"
    });
  };

  // set up push
  subscribePush();
}

subscribePush = () => {
  fetch("vapid-public-key")
    .then(function(response) {
      response.arrayBuffer().then(function(buffer) {
        var publicKey = new Uint8Array(buffer);
        navigator.serviceWorker.ready
          .then(function(serviceWorkerRegistration) {
            serviceWorkerRegistration.pushManager
              .subscribe({
                userVisibleOnly: true,
                applicationServerKey: publicKey
              })
              .then(function(subscription) {
                var auth = base64ArrayBuffer(subscription.getKey("auth"));
                var p256dh = base64ArrayBuffer(subscription.getKey("p256dh"));
                var data = {
                  endpoint: subscription.endpoint,
                  auth: auth,
                  p256dh: p256dh
                };
                fetch("api/subscription", {
                  method: "POST",
                  headers: {
                    "Content-Type": "application/json; charset=utf-8"
                  },
                  body: JSON.stringify(data)
                });
              });
          })
          .catch(function(e) {
            console.error("Unable to subscribe to push.", e);
          });
      });
    })
    .catch(function(error) {
      console.log("Looks like there was a problem: \n", error);
    });
};
