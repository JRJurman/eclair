#!/bin/sh
set -e

mkdir -p dist

clang -dynamiclib -fobjc-arc -fvisibility=hidden \
  -arch arm64 -arch x86_64 -mmacosx-version-min=10.14 \
  -install_name @rpath/libeclair.dylib \
  -Wall -Wextra -I./src \
  src/eclair.c src/eclair_apple.m \
  -framework AppKit -framework AVFoundation -framework Foundation \
  -o dist/libeclair.dylib
