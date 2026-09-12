#!/bin/sh
set -e

FLAGS="-Wall -Wextra -Wstrict-prototypes -pedantic -fsyntax-only -I./src"

# validate header files are correct for c and c++
for h in src/*.h; do
	echo "#include \"$(basename "$h")\"" | clang   -std=c99   $FLAGS -x c -
	echo "#include \"$(basename "$h")\"" | clang++ -std=c++11 $FLAGS -x c++ -
done

# validate c files are correct
for c in src/*.c; do
	clang -std=c99 $FLAGS "$c"
done

# validate c++ files are correct
for cc in src/*.cpp; do
	clang++ -std=c++11 $FLAGS "$cc"
done

# validate objective-c files are correct (apple only)
if [ "$(uname -s)" = "Darwin" ]; then
	clang -c -fobjc-arc -Wall -Wextra -Isrc src/eclair_apple.m -o /tmp/apple.o
fi

# validate the web backend (emscripten)
# NOTE: this requires sourcing emsdk_env.sh from emsdk repo
if command -v emcc > /dev/null 2>&1; then
	emcc -std=c99 $FLAGS src/eclair_web.c
else
	echo "emcc not found - skipping emscripten check"
fi

# validate the web backend's js library (node)
if command -v node > /dev/null 2>&1; then
	node scripts/weak-typecheck-web.js src/eclair_web.js
else
	echo "node not found - skipping js library check"
fi
