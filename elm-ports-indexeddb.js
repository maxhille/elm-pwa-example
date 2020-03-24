var ElmPortsIndexedDB = {
	dbs : {},
	bind: function(app) {
		app.ports.idxdbInitRequest.subscribe(dbName => {
			var request = indexedDB.open(dbName);
			request.onerror = function(event) {
				// TODO are there error msgs or something?
				app.ports.idxdnInitResponse.send({
					"dbName": dbName,
					"result": "error"
				})
			};
			request.onsuccess = function(event) {
				db = event.target.result;
				app.ports.idxdnInitResponse.send({
					"dbName": dbName,
					"result": "success"
				})
			};
			request.onupgradeneeded = function(event) {
				var db = event.target.result;
				app.ports.idxdnInitResponse.send({
					"dbName": dbName,
					"result": "upgrade-needed"
				})
				db.createObjectStore("posts", {
					keyPath: "id"
				});
			};
		});
	}
};
