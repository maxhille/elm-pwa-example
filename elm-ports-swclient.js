var ElmPortsSWClient = {
    bind: function(app) {
        app.ports.availabilityRequest.subscribe(() => {
            var available = "serviceWorker" in navigator;
            app.ports.availabilityResponse.send(available);
        });

        app.ports.registrationRequest.subscribe(() => {
            navigator.serviceWorker.register("/service-worker.js").then(
                registration => {
                    app.ports.registrationResponse.send("success")
                },
                err => {
                    app.ports.registrationResponse.send("error")
                }
            );
        });
    }
};
