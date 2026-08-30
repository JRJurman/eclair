#!/bin/sh
set -e

VSWHERE="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"

if [ ! -f "$VSWHERE" ]; then
	echo "vswhere not found - install Visual Studio Build Tools" >&2
	exit 1
fi

# vswhere prints a windows path, with CRLF line endings
VSPATH=$("$VSWHERE" -latest -products '*' -property installationPath | tr -d '\r')
VCVARS=$(cygpath -w "$VSPATH/VC/Auxiliary/Build/vcvars64.bat")

# intermediates land here, and are removed once the build succeeds
mkdir -p dist/obj

# git bash escapes embedded double quotes as \" when building the windows
# command line, and cmd reads those backslashes
cat > dist/obj/build.bat <<EOF
@echo off
call "$VCVARS" >nul || exit /b 1
cl -nologo -LD -MD -W4 -EHsc -DECLAIR_BUILD_SHARED -I src ^
	src/eclair.c src/eclair_windows.cpp ^
	-Fe:dist/eclair.dll -Fo:dist/obj/ ole32.lib sapi.lib oleaut32.lib user32.lib || exit /b 1
EOF

cmd //c "$(cygpath -w dist/obj/build.bat)"

# clean up unused resources
rm -rf dist/obj
rm -f dist/eclair.lib dist/eclair.exp
