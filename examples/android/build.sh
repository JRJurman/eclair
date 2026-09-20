#!/bin/sh
set -e

# Builds and installs the Android test harness.
# This is a harness build, not a library build
#
#   ./examples/android/build.sh              build only
#   ./examples/android/build.sh --run        build, install and launch
#   ./examples/android/build.sh --abi=x86_64 build for another ABI
#
# Override the toolchain locations with ANDROID_HOME and ANDROID_NDK_HOME.

# Run from anywhere: every path below is derived from this script's own
# location rather than the working directory.
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)

ABI="${ECLAIR_ABI:-arm64-v8a}"
RUN=""

# eclair's floor: the lowest level needing no deprecated-API branch, and the
# level baked into the NDK's clang wrapper name below.
API=21
TARGET_API=36

for arg in "$@"; do
	case "$arg" in
		--run)   RUN=1 ;;
		--abi=*) ABI="${arg#--abi=}" ;;
		*)
			echo "unknown argument: $arg" >&2
			echo "usage: $0 [--run] [--abi=arm64-v8a|armeabi-v7a|x86_64]" >&2
			exit 1
			;;
	esac
done

# ---------------------------------------------------------------
# locate the toolchains
# ---------------------------------------------------------------

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"

if [ ! -d "$SDK" ]; then
	echo "Android SDK not found at $SDK - set ANDROID_HOME" >&2
	exit 1
fi

# Newest installed, chosen lexically. "36.1.0" beats "35.0.0" and "android-36.1"
# beats "android-35", which holds for every version anyone has installed today.
BUILD_TOOLS="$SDK/build-tools/$(ls "$SDK/build-tools" | sort | tail -1)"
ANDROID_JAR="$SDK/platforms/$(ls "$SDK/platforms" | sort | tail -1)/android.jar"

NDK="${ANDROID_NDK_HOME:-$(ls -d "$SDK"/ndk/* 2>/dev/null | sort | tail -1)}"

if [ ! -d "$NDK" ]; then
	echo "Android NDK not found under $SDK/ndk - set ANDROID_NDK_HOME" >&2
	exit 1
fi

case "$(uname -s)" in
	Darwin) HOST_TAG=darwin-x86_64 ;;
	Linux)  HOST_TAG=linux-x86_64 ;;
	*)
		echo "unsupported build host: $(uname -s)" >&2
		exit 1
		;;
esac

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"

# The NDK ships one clang wrapper per target triple and API level; the level is
# part of the filename rather than a flag.
case "$ABI" in
	arm64-v8a)   CC="$TOOLCHAIN/aarch64-linux-android$API-clang" ;;
	armeabi-v7a) CC="$TOOLCHAIN/armv7a-linux-androideabi$API-clang" ;;
	x86_64)      CC="$TOOLCHAIN/x86_64-linux-android$API-clang" ;;
	*)
		echo "unsupported ABI: $ABI" >&2
		exit 1
		;;
esac

# ---------------------------------------------------------------
# build
# ---------------------------------------------------------------

OUT="$HERE/build"
WORK="$OUT/work"

rm -rf "$WORK"
mkdir -p "$WORK/lib/$ABI" "$WORK/classes" "$WORK/dex"

# 16 KB page support. The NDK's CMake and ndk-build toolchains add this flag
# themselves; invoking clang directly does not, and without it the library
# loads on every 4 KB-page device anyone owns and fails on Android 15+ hardware
# with 16 KB pages.
PAGE_FLAGS="-Wl,-z,max-page-size=16384"

echo "==> libeclair.so ($ABI, API $API)"

# No -llog and no C++ runtime: eclair_android.c is plain C and does no logging,
# which is what keeps the NEEDED list at libc and libdl - the property readelf
# confirms on Linux, holding here too.
"$CC" -shared -fPIC -std=c99 \
	-fvisibility=hidden -DECLAIR_BUILD_SHARED \
	$PAGE_FLAGS \
	-Wall -Wextra -I"$ROOT/src" \
	"$ROOT/src/eclair.c" "$ROOT/src/eclair_android.c" \
	-o "$WORK/lib/$ABI/libeclair.so"

echo "==> libharness.so"

"$CC" -shared -fPIC -std=c99 \
	$PAGE_FLAGS \
	-Wall -Wextra -I"$ROOT/src" \
	"$HERE/harness.c" \
	-L"$WORK/lib/$ABI" -leclair \
	-o "$WORK/lib/$ABI/libharness.so"

# Read the alignment back out rather than trusting the flag went in.
ALIGN=$("$TOOLCHAIN/llvm-readelf" -l "$WORK/lib/$ABI/libeclair.so" \
	| awk '$1 == "LOAD" { print $NF }' | sort -u | tr '\n' ' ')
echo "    LOAD alignment: $ALIGN (want 0x4000)"

echo "==> javac"

# -source/-target 8 rather than --release 8, because android.jar has to be the
# bootclasspath: the Java 8 platform classes it would otherwise compile against
# are not the ones on the device.
#
# -Xlint:-options silences JDK 21's "source value 8 is obsolete". Deprecation
# warnings are deliberately left on - TYPE_ANNOUNCEMENT is deprecated as of
# API 36, and that warning is information, not noise.
javac -source 8 -target 8 \
	-Xlint:-options -Xlint:deprecation \
	-bootclasspath "$ANDROID_JAR" \
	-d "$WORK/classes" \
	"$ROOT"/src/java/org/eclair/*.java \
	"$HERE/HarnessActivity.java"

echo "==> d8"

# d8 desugars the lambdas and default methods javac emitted for source 8.
"$BUILD_TOOLS/d8" \
	--min-api "$API" \
	--lib "$ANDROID_JAR" \
	--output "$WORK/dex" \
	$(find "$WORK/classes" -name '*.class')

echo "==> aapt2"

# Manifest only - the harness builds its UI in code, so there is no res/ to
# compile and no R.java to generate.
"$BUILD_TOOLS/aapt2" link \
	-I "$ANDROID_JAR" \
	--manifest "$HERE/AndroidManifest.xml" \
	--min-sdk-version "$API" \
	--target-sdk-version "$TARGET_API" \
	-o "$WORK/base.apk"

echo "==> package"

# An APK is a zip, and zip appends. android:extractNativeLibs="true" in the
# manifest lets the .so files stay compressed, which is why no page-alignment
# of the archive itself is needed here.
cp "$WORK/dex/classes.dex" "$WORK/classes.dex"
( cd "$WORK" && zip -q -r base.apk classes.dex "lib/$ABI" )

"$BUILD_TOOLS/zipalign" -f -p 4 "$WORK/base.apk" "$WORK/aligned.apk"

echo "==> sign"

# A throwaway signing key
KEYSTORE="$OUT/debug.keystore"

if [ ! -f "$KEYSTORE" ]; then
	echo "    generating $KEYSTORE"
	keytool -genkeypair \
		-keystore "$KEYSTORE" \
		-storepass android -keypass android \
		-alias eclairharness \
		-keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=eclair harness" 2>/dev/null
fi

"$BUILD_TOOLS/apksigner" sign \
	--ks "$KEYSTORE" \
	--ks-pass pass:android --key-pass pass:android \
	--min-sdk-version "$API" \
	--out "$OUT/eclair-harness.apk" \
	"$WORK/aligned.apk"

APK="$OUT/eclair-harness.apk"

echo
echo "built ${APK#"$ROOT"/}"

if [ -n "$RUN" ]; then
	echo
	adb install -r "$APK"
	adb shell am start -n org.eclair.harness/.HarnessActivity
else
	echo
	echo "  adb install -r ${APK#"$ROOT"/}"
	echo "  adb shell am start -n org.eclair.harness/.HarnessActivity"
	echo "  adb logcat"
fi
