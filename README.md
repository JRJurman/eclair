# eclair

![cartoon of half an eclair pastry with a glossy chocolate top and white filling](./eclair.png)

_Embedded Cross-platform Library for Assistive Interface Routing_

Eclair is a small library for enabling Blind and Low-Vision support in
applications and game engines. It provides a simple API to send text to Screen
Readers and Synthesizers, turning that text into audible speech. It is specifically
designed to be small, simple, and embeddable into games and game engines.

## Platform Support

Eclair supports all major desktop and mobile platforms, as well as web applications.
* macOS and iOS with VoiceOver and AVSpeech
* Windows with NVDA, JAWS, Narrator, and SAPI
* Linux with Orca and Speech Dispatcher
* Android with AccessibilityManager (TalkBack) and TextToSpeech
* Web with ariaNotify and Web Speech API

Some braille support does exist for screen readers that support them.

## Motivation

* Small API
* Automatic routing
* Zero dependencies
* No externally linked packages
* Small bundle size

## Example

```c
#include "eclair.h"

// when your application starts
eclair_init();

// when the selection moves, cut off whatever is still being read
eclair_speak("Start Game, 1 of 3", true);

// when something happens on its own, let the current speech finish
eclair_speak("Checkpoint reached", false);

// when your application exits
eclair_shutdown();
```

Eclair only sends text - developers are responsible for giving clear information
to users on what is being shown, what kind of control they are currently selecting,
and what options they have.

Eclair is well suited for non-standard applications and interfaces that don't
mimic standard buttons or controls. If you are using more standard application
interfaces, you may want to look at [AccessKit](https://accesskit.dev/) instead.

## API

<dl>
<dt><code>eclair_init()</code></dt>
<dd>
Initialization function that starts up eclair on the platform it is loaded on.
</dd>

<dt><code>eclair_shutdown()</code></dt>
<dd>
Shutdown function that stops eclair and removes and platform hooks set up.
</dd>

<dt><code>eclair_speak(char *utf8, bool interrupt)</code></dt>
<dd>
Main function to send text to a Screen Reader to Text to Speech Synthesizer.
Takes in a string to read out, and an <code>interrupt</code> parameter, which may stop the previous speak command.

Expects a UTF8 string (strings containing non-UTF8 characters will be rejected).
Interrupt is best-effort, some Screen Readers and Synthesizers might always stop the ongoing read out.
</dd>

<dt><code>eclair_stop()</code></dt>
<dd>
Function to stop the current read out.

This is best-effort - some screen readers, like VoiceOver and <code>ariaNotify</code>, expose no way to cancel an announcement, so the call does nothing there and still reports <code>ECLAIR_OK</code>.
</dd>

<dt><code>eclair_set_route(eclair_route route)</code></dt>
<dd>
Function to specifically choose whether text should be sent to a screen reader or a synthesizer.

By default, this is set to <code>ECLAIR_ROUTE_PREFER_SCREEN_READER</code>, which will connect to a screen reader if available,
and fall back to a synthesizer when no screen reader is present.
</dd>

<dt><code>eclair_set_rate(float rate)</code></dt>
<dd>
Function to set how fast the text should be read out. This only applies to synthesizers (not screen readers).

The default value is 1.0, and the valid range is 0.5 (around half-speed) to 4.0 (four times as fast).
Actual rates may vary across platforms. Some platforms (namely Android) may default at a platform speed.
</dd>

<dt><code>eclair_set_volume(float volume)</code></dt>
<dd>
Function to set how loud the synthesizer is. This only applies to synthesizers (not screen readers).

The default value is 1.0, and the valid range is 0.0 (silent) to 1.0 (full volume).
</dd>

<dt><code>eclair_current_output()</code></dt>
<dd>
Function to get the current backend type, either a synthesizer or screen reader. This is useful for
determining if you should expose synthesizer specific controls (such as volume and rate).
</dd>

<dt><code>eclair_backend_name()</code></dt>
<dd>
Function to get the name of the specific screen reader or synthesizer being used. Mostly a debugging / diagnostics tool.
</dd>

<dt><code>eclair_error_string(eclair_error err)</code></dt>
<dd>
Function to get the english description of what an error code means. Mostly a debugging / diagnostics tool.
</dd>

</dl>

## Testing

You can run the examples in the `/examples` directory of this project to test the different controls and behaviors on different platforms. You'll need to install and enable screen readers for any platform that you are testing on. These tests are made to run on real hardware.

## Inspirations and Alternatives

Eclair is heavily inspired by [SRAL (now archived)](https://github.com/m1maker/SRAL) and [Prism](https://github.com/ethindp/prism).

## Development

This project is in active development. There is a long list of tasks still to be completed. If you are interested in helping or would like help integrating into your own project, feel free to start a [discussion](https://github.com/JRJurman/eclair/discussions/categories/general).

## Logo

The above logo was created by Jesse Jurman and Eva Jurman
