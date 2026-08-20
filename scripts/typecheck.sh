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
