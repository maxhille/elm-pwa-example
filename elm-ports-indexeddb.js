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
                ElmPortsIndexedDB.dbs[opts.name] = event.target.result;
                app.ports.openResponseInternal.send({
                    name: opts.name,
                    result: "upgrade-needed"
                });
            };
        });

        app.ports.createObjectStoreInternal.subscribe(opts => {
            var db = ElmPortsIndexedDB.dbs[opts.db];
            db.createObjectStore(opts.name);
            app.ports.createObjectStoreResultInternal.send(opts.name);
        });

        app.ports.queryInternal.subscribe(opts => {
            // https://developer.mozilla.org/en-US/docs/Web/API/IDBObjectStore/get
            var db = ElmPortsIndexedDB.dbs[opts.db];
            var tx = db.transaction([opts.name], "readwrite");
            var store = tx.objectStore(opts.name);
            var req = store.get("key");
            req.onsuccess = ev => {
                app.ports.queryResultInternal.send(req.result);
            };
        });

        app.ports.putInternal.subscribe(opts => {
            // https://developer.mozilla.org/en-US/docs/Web/API/IDBObjectStore/put
            var db = ElmPortsIndexedDB.dbs[opts.db];
            var tx = db.transaction([opts.name], "readwrite");
            var store = tx.objectStore(opts.name);
            var req = store.put(opts.data, opts.key);
            req.onsuccess = ev => {
//                app.ports.putResultInternal.send({});
            };
        });
    }
};
