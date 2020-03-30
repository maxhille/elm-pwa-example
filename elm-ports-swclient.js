var ElmPortsSWClient = {
    registration: null,
    bind: function(app) {
        app.ports.availabilityRequest.subscribe(() => {
            var available = "serviceWorker" in navigator;
            app.ports.availabilityResponse.send(available);
        });

        app.ports.registrationRequest.subscribe(() => {
            navigator.serviceWorker.register("/service-worker.js").then(
                registration => {
                    if (this.registration != null) {
                        console.log("I already have a registration :-(");
                        return;
                    }

                    this.registration = registration;
                    app.ports.registrationResponse.send("success");
                },
                err => {
                    app.ports.registrationResponse.send("error");
                }
            );
        });

        navigator.serviceWorker.onmessage = app.ports.onMessage;

        app.ports.postMessageInternal.subscribe(() => {
            if (!this.registration.active) {
                console.log("could not post msg: SW not active");
                return;
            }
            var sw = this.registration.active;
            sw.postMessage("dummy");
        });
    }
};
