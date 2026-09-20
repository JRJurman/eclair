#!/bin/sh
set -e

# Builds and installs the iOS test harness.
# This is a harness build, not a library build - eclair is compiled from
# source into the app, which is the vendoring instruction rather than a
# prebuilt, and on iOS it is the only mode there is.
#
#   ./examples/ios/build.sh              build for a device
#   ./examples/ios/build.sh --run        build, install and launch on a device
#   ./examples/ios/build.sh --release    Release rather than Debug
#   ./examples/ios/build.sh --run --no-direct-touch
#
# The canvas carries UIAccessibilityTraitAllowsDirectInteraction by default,
# because a game that ships accessibility needs it, and a shipping one adds
# its own iOS logic for exactly this. --no-direct-touch launches the same build
# without it, which is what stock SDL_uikitview.m presents, and is there to
# show what that costs rather than to be used.
#
# Device only. The simulator does not run VoiceOver, so it can exercise the
# synthesizer route and nothing else - and this is the platform whose whole
# lesson was that testing outside the shipping configuration measures the
# harness rather than the library.
#
# Signing is automatic. The team is read from the installed Apple Development
# certificate; override it with ECLAIR_TEAM_ID, and pick a device other than
# the first one found with ECLAIR_IOS_DEVICE.

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)

BUNDLE_ID=org.eclair.harness
CONFIG=Debug
RUN=""
LAUNCH_ARGS=""

for arg in "$@"; do
	case "$arg" in
		--run)     RUN=1 ;;
		--release) CONFIG=Release ;;
		--no-direct-touch) LAUNCH_ARGS="-directTouch NO" ;;
		*)
			echo "unknown argument: $arg" >&2
			echo "usage: $0 [--run] [--release] [--no-direct-touch]" >&2
			exit 1
			;;
	esac
done

if ! xcode-select -p > /dev/null 2>&1; then
	echo "Xcode command line tools not found - run xcode-select --install" >&2
	exit 1
fi

OUT="$HERE/build"

# ---------------------------------------------------------------
# resolve the signing team
# ---------------------------------------------------------------
#
# Required: without DEVELOPMENT_TEAM, automatic signing fails outright with
# "Signing for Harness requires a development team", and there is nothing in
# the checked-in project for it to fall back on - deliberately, since a team id
# baked into the pbxproj is one person's and breaks for everyone else.
#
# It is the OU of the Apple Development certificate, not the parenthetical in
# its CN. Those differ on an account that also holds a Developer ID, and the CN
# value fails with "No Account for Team" - measured, not assumed. The obvious
# shorter route, `security find-identity`, prints only the CN, which is why
# this reads the subject through openssl instead. The first certificate wins;
# ECLAIR_TEAM_ID is the override when there is more than one team.

TEAM="${ECLAIR_TEAM_ID:-$(security find-certificate -c "Apple Development" -p 2>/dev/null \
	| openssl x509 -noout -subject 2>/dev/null \
	| sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')}"

if [ -z "$TEAM" ]; then
	echo "no Apple Development certificate found - sign in to Xcode under" >&2
	echo "Settings > Accounts, or set ECLAIR_TEAM_ID to your team id" >&2
	exit 1
fi

echo "==> team $TEAM"

# ---------------------------------------------------------------
# build
# ---------------------------------------------------------------
#
# -allowProvisioningUpdates lets Xcode register the device and mint the
# profile on first run; there is nothing checked in for it to find.

echo "==> build ($CONFIG)"

xcodebuild \
	-project "$HERE/Harness.xcodeproj" \
	-target Harness \
	-configuration "$CONFIG" \
	-sdk iphoneos \
	SYMROOT="$OUT" OBJROOT="$OUT/obj" \
	-allowProvisioningUpdates \
	DEVELOPMENT_TEAM="$TEAM" \
	build

APP="$OUT/$CONFIG-iphoneos/Harness.app"

echo
echo "built ${APP#"$ROOT"/}"

if [ -z "$RUN" ]; then
	echo
	echo "  $0 --run"
	exit 0
fi

# ---------------------------------------------------------------
# install and launch
# ---------------------------------------------------------------

# Both UDID shapes: the 8-16 form modern iPhones use, and the flat 40-hex
# form of everything before the A12.
UDID="${ECLAIR_IOS_DEVICE:-$(xcrun devicectl list devices 2>/dev/null \
	| grep -Eo '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40}' \
	| head -1)}"

if [ -z "$UDID" ]; then
	echo "no paired device found - connect and unlock the iPhone, or set" >&2
	echo "ECLAIR_IOS_DEVICE to its udid (xcrun devicectl list devices)" >&2
	exit 1
fi

echo
echo "==> install ($UDID)"
xcrun devicectl device install app --device "$UDID" "$APP"

echo "==> launch"
xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID" -- $LAUNCH_ARGS

echo
echo "  logs: xcrun devicectl device console --device $UDID"
