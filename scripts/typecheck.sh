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

# resolve the android sdk and ndk the same way examples/android/build.sh does
ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ANDROID_NDK="${ANDROID_NDK_HOME:-$(ls -d "$ANDROID_SDK"/ndk/* 2>/dev/null | sort | tail -1)}"

case "$(uname -s)" in
	Darwin) NDK_HOST=darwin-x86_64 ;;
	*)      NDK_HOST=linux-x86_64 ;;
esac

NDK_CC="$ANDROID_NDK/toolchains/llvm/prebuilt/$NDK_HOST/bin/aarch64-linux-android21-clang"

# validate the android backend (ndk)
if [ -x "$NDK_CC" ]; then
	"$NDK_CC" -std=c99 $FLAGS src/eclair_android.c
else
	echo "android ndk not found - skipping android check"
fi

# validate the android java backend (javac against android.jar)
ANDROID_JAR="$ANDROID_SDK/platforms/$(ls "$ANDROID_SDK/platforms" 2>/dev/null | sort | tail -1)/android.jar"

if [ -f "$ANDROID_JAR" ] && command -v javac > /dev/null 2>&1; then
	javac -source 8 -target 8 -Xlint:-options -Xlint:all \
		-bootclasspath "$ANDROID_JAR" \
		-d /tmp/eclair-typecheck-java \
		src/java/org/eclair/*.java
else
	echo "android.jar or javac not found - skipping android java check"
fi
