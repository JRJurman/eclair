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
Starts eclair and connects to the running platform.
</dd>

<dt><code>eclair_shutdown()</code></dt>
<dd>
Stops eclair and unloads any backend connections.
</dd>

<dt><code>eclair_speak(char *utf8, bool interrupt)</code></dt>
<dd>
Sends text to whichever backend the current route resolves to. Pass <code>true</code> for <code>interrupt</code> to ask that whatever is currently being spoken be cut off first; this is best-effort, since not every screen reader allows it.
</dd>

<dt><code>eclair_stop()</code></dt>
<dd>
Asks the active backend to stop speaking immediately.

This is best-effort - some screen readers, like VoiceOver and <code>ariaNotify</code>, expose no way to cancel an announcement, so the call does nothing there and still reports <code>ECLAIR_OK</code>.
</dd>

<dt><code>eclair_set_route(eclair_route route)</code></dt>
<dd>
Chooses which types of backends to send text to: off entirely, screen readers only, synthesizers only, or screen reader with a synthesizer fallback. The default is <code>ECLAIR_ROUTE_PREFER_SCREEN_READER</code>. Takes effect on the next call to <code>eclair_speak()</code>.
</dd>

<dt><code>eclair_set_rate(float rate)</code></dt>
<dd>
Sets how fast speech is spoken, from <code>0.0</code> (slowest) to <code>1.0</code> (fastest), defaulting to <code>0.5</code>. This only affects synthesizers - screen readers speak at the rate the user configured.
</dd>

<dt><code>eclair_set_volume(float volume)</code></dt>
<dd>
Sets speech volume, from <code>0.0</code> (silent) to <code>1.0</code> (full), defaulting to <code>1.0</code>. Like the rate, this applies to synthesizers only.
</dd>

<dt><code>eclair_current_output()</code></dt>
<dd>
Reports where text would go right now - a screen reader, a synthesizer, or nothing at all - by resolving the current route against what is available.
</dd>

<dt><code>eclair_backend_name()</code></dt>
<dd>
Returns the name of the backend currently being used, such as <code>"NVDA"</code>, <code>"VoiceOver"</code>, or <code>"Speech Dispatcher"</code>, or NULL when there is none. Intended for display and debugging - branch on <code>eclair_current_output()</code> instead of comparing this string.
</dd>

<dt><code>eclair_error_string(eclair_error err)</code></dt>
<dd>
Returns a short English description of an error code, useful for logging and debugging. The strings are static and not translated, so they are not meant to be shown to end users.
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
