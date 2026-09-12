#!/bin/sh
set -e

if ! command -v emcc > /dev/null 2>&1; then
	echo "emcc not found - source emsdk_env.sh from your emsdk checkout first" >&2
	exit 1
fi

mkdir -p dist

# the ten public functions, named explicitly. this list is the web counterpart of the ECLAIR_API macro
EXPORTS='_eclair_init,_eclair_shutdown,_eclair_speak,_eclair_stop'
EXPORTS="$EXPORTS,_eclair_set_route,_eclair_set_rate,_eclair_set_volume"
EXPORTS="$EXPORTS,_eclair_current_output,_eclair_backend_name,_eclair_error_string"

emcc -std=c99 -Os -Wall -Wextra -I./src \
	src/eclair.c src/eclair_web.c \
	--js-library src/eclair_web.js \
	--no-entry \
	-sEXPORTED_FUNCTIONS="$EXPORTS" \
	-sEXPORTED_RUNTIME_METHODS=ccall,cwrap \
	-sMODULARIZE=1 \
	-sEXPORT_NAME=Eclair \
	-o dist/eclair.js
