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


const subscribePush = () => {
    fetch("vapid-public-key")
        .then(function(response) {
            response.text().then(function(str) {
                var publicKey = urlBase64ToUint8Array(str);
                navigator.serviceWorker.ready
                    .then(function(serviceWorkerRegistration) {
                        serviceWorkerRegistration.pushManager
                            .subscribe({
                                userVisibleOnly: true,
                                applicationServerKey: publicKey
                            })
                            .then(function(subscription) {
                                var auth = base64ArrayBuffer(
                                    subscription.getKey("auth")
                                );
                                var p256dh = base64ArrayBuffer(
                                    subscription.getKey("p256dh")
                                );
                                var data = {
                                    endpoint: subscription.endpoint,
                                    auth: auth,
                                    p256dh: p256dh
                                };
                                fetch("api/subscription", {
                                    method: "POST",
                                    headers: {
                                        "Content-Type":
                                            "application/json; charset=utf-8"
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
/**
 *  * urlBase64ToUint8Array
 *   *
 *    * @param {string} base64String a public vavid key
 *     */
function urlBase64ToUint8Array(base64String) {
    var padding = "=".repeat((4 - (base64String.length % 4)) % 4);
    var base64 = (base64String + padding)
        .replace(/\-/g, "+")
        .replace(/_/g, "/");

    var rawData = window.atob(base64);
    var outputArray = new Uint8Array(rawData.length);

    for (var i = 0; i < rawData.length; ++i) {
        outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
}

var app = Elm.Main.init();
ElmPortsSWClient.bind(app);
