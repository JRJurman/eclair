# ios/

The iOS test harness.

Runs on a connected device and exposes the same controls as the Tk and Android
harnesses, driving the ten public functions and nothing else.

Everything is drawn on one view and hit-tested by hand, where the other two
harnesses use the platform's own widgets — see [Why a canvas](#why-a-canvas).
The one thing that costs is typing: a canvas has no text field, so the ability
to speak different strings arrives as a list the Text control cycles through.

eclair is compiled from source into the app rather than linked as a library —
which is the vendoring instruction rather than a prebuilt, and on iOS it is the
only mode there is. Unlike Android there is no shim: Objective-C calls eclair's
C directly, and `harness.c` exists over there only because that harness is
written in Java.

## Building

```sh
./examples/ios/build.sh              # build for a device
./examples/ios/build.sh --run        # build, install and launch
./examples/ios/build.sh --release    # Release rather than Debug
./examples/ios/build.sh --run --no-direct-touch
```

Signing is automatic — `xcodebuild -allowProvisioningUpdates` registers the
device and mints the profile on first run, so nothing is checked in for it to
find. The team is read from the installed Apple Development certificate;
override it with `ECLAIR_TEAM_ID`. With more than one device paired, pick one
with `ECLAIR_IOS_DEVICE=<udid>` (`xcrun devicectl list devices`).

Logs:

```sh
xcrun devicectl device console --device <udid>
```

## Device only

The simulator is not supported. It runs AVSpeech but **not VoiceOver**, so
`eclair_sr_available()` is false there by construction and every screen reader
row needs real hardware — and this is the platform whose whole lesson was that
testing outside the shipping configuration measures the harness rather than
the library.

## Why a canvas

iOS is the one platform where a widget harness cannot test the screen reader
route at all. With VoiceOver running, every button press is a VoiceOver
activation, and an announcement posted inside one is dropped while VoiceOver
speaks the control's own label — measured on an iPhone 13 mini running
iOS 26.6.2, where a plain `UIAccessibilityPostNotification` from a `UIButton`
handler is silent and the identical post from a timer three seconds later is
heard.

A game is never in that situation. It draws its own interface and calls
`eclair_speak()` from its frame loop, so a widget harness measures the harness
rather than the library. Drawing the controls and hit-testing them by hand puts
the harness in the same position the library's actual consumer is in.

It is also the same position literally: `SDL_uikitview.m` sets no accessibility
properties whatsoever — not `isAccessibilityElement`, not `accessibilityTraits`
— so one view with no accessibility elements is exactly what a game built on
SDL presents to VoiceOver.

## Direct touch

A view with no accessibility elements has nothing for VoiceOver to focus, and
therefore nothing for it to pass a touch to. So the canvas carries
`UIAccessibilityTraitAllowsDirectInteraction` — the trait UIKit documents for
"a view representing a piano keyboard" — and that is its entire accessibility
surface.

This is not the harness compensating for being a canvas. Stock
`SDL_uikitview.m` has the same problem, and a shipping game carries its own iOS
logic to solve it — so anything that wants a blind player to be able to touch
its interface has to say so itself. The harness presenting what a shipping game
presents is the point.

`--no-direct-touch` launches the same build without the trait, which is what
stock SDL gives you. It is there to show what that costs, not to be used.
