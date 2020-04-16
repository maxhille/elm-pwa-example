var ElmPortsIndexedDB = {
    dbs: {},
    bind: function(app) {
        app.ports.openRequestInternal.subscribe(opts => {
            var request = indexedDB.open(opts.name, opts.version);
            request.onerror = function(event) {
                // TODO are there error msgs or something?
                app.ports.openResponseInternal.send({
                    name: opts.name,
                    result: "error"
                });
            };
            request.onsuccess = function(event) {
                ElmPortsIndexedDB.dbs[opts.name] = event.target.result;
                app.ports.openResponseInternal.send({
                    name: opts.name,
                    result: "success"
                });
            };
            request.onupgradeneeded = function(event) {
                var db = event.target.result;
                app.ports.openResponseInternal.send({
                    name: opts.name,
                    result: "upgrade-needed"
                });
            };
        });

        //app.ports.createObjectStore.subscribe(opts => {
        //    db.createObjectStore("posts", {
        //        keyPath: "id"
        //    });
        //});
    }
};
