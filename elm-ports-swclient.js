var ElmPortsSWClient = {
    bind: function(app) {
        app.ports.availabilityRequest.subscribe(() => {
            var available = "serviceWorker" in navigator;
            app.ports.availabilityResponse.send(available);
        });
    }
};
