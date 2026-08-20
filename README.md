# eclair
_Embedded Cross-platform Library for Assistive Interface Routing_

Eclair is a library used for enabling Blind and Low-Vision support in
applications and game engines. It provides a simple API to send text to Screen
Readers and Synthesizers, turning that text into audible speech. It is specifically
designed to be small, simple, and embeddable into games and game engines.

## Example

```c
eclair_init()
eclair_speak("Press Start to begin", true)
```

Eclair only sends text - developers are responsible for giving clear information
to users on what is being shown, what kind of control they are currently selecting,
and what options they have.

Eclair is well suited for non-standard applications and interfaces that don't
mimic standard buttons or controls. If you are using more standard application
interfaces, you may want to look at [AccessKit](https://accesskit.dev/) instead.

## Supported Platforms

To be filled...

## API

```c
// lifecycle functions
eclair_error eclair_init(void);
void eclair_shutdown(void);

// output function
eclair_error eclair_speak(const char *utf8, bool interrupt)
eclair_error eclair_stop(void)

// settings and introspection
void eclair_set_route(eclair_route route)
void eclair_set_rate(float rate)
void eclair_set_volume(float volume)
eclair_output eclair_current_output(void)
```

## Inspirations and Alternatives

Eclair is heavily inspired by [SRAL (now archived)](https://github.com/m1maker/SRAL) and [Prism](https://github.com/ethindp/prism).
