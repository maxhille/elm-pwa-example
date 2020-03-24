elm = build/elm.js build/elm-worker.js

all: $(elm)

clean:
	rm -rf build

$(elm): *.elm
	mkdir -p build
	elm make Main.elm --output build/elm.js
	elm make Worker.elm --output build/elm-worker.js
