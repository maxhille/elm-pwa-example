elm = build/elm.js

all: $(elm)

clean:
	rm -rf build

$(elm): Main.elm
	mkdir -p build
	elm make Main.elm --output build/elm.js
