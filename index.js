var db;

function post(text) {
    var post = {
        text: text
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
    app.ports.refreshPosts.subscribe(() => {
        refreshPosts();
    });
}

var app = Elm.Main.init();
ElmPortsSWClient.bind(app);
