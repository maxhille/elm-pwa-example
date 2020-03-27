var ElmPortsSWClient = {
    bind: function(app) {
        app.ports.availabilityRequest.subscribe(() => {
            var available = "serviceWorker" in navigator;
            app.ports.availabilityResponse.send(available);
        });

        app.ports.registrationRequest.subscribe(() => {
            navigator.serviceWorker.register("/service-worker.js").then(
                registration => {
                    console.log("registration success");
                },
                err => {
                    console.log("registration error");
                }
            );
        });
    }
};
