#!/bin/sh
set -e

mkdir -p dist

clang -dynamiclib -fobjc-arc -fvisibility=hidden -Wall -Wextra -I./src \
  src/eclair.c src/eclair_apple.m \
  -framework AppKit -framework AVFoundation -framework Foundation \
  -o dist/libeclair.dylib
