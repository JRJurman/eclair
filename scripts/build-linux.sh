#!/bin/sh
set -e

mkdir -p dist

# no -lspeechd and no -ldbus-1: both clients are resolved at runtime, so the
# shipped library declares no DT_NEEDED beyond libc
clang -shared -fPIC -std=c99 -fvisibility=hidden -DECLAIR_BUILD_SHARED \
      -Wall -Wextra -I./src \
      src/eclair.c src/eclair_linux.c \
      -o dist/libeclair.so
