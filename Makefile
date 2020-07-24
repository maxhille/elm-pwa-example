.PHONY: all clean serve

elm = build/elm.js build/elm-worker.js

go_src = app/*.go cmd/local/*.go
elm_src = *.elm

all: $(elm) build/srv 

clean:
	rm -rf build

$(elm): $(elm_src)
	mkdir -p build
	elm make Main.elm --output build/elm.js --debug
	elm make Worker.elm --output build/elm-worker.js --debug

build/srv: $(go_src)
	mkdir -p build
	go build -o build/srv cmd/local/main.go 

serve:
	export DATASTORE_EMULATOR_HOST=localhost:8081; \
	while true; do \
		kill `cat .pid`; \
		clear ;\
		make all; \
		build/srv & echo $$! > .pid ;\
		inotifywait -qre close_write $(elm_src) $(go_src); \
	done
