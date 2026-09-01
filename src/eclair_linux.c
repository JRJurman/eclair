/*
 * eclair - Linux backend: Orca (screen reader), Speech Dispatcher (synthesizer)
 * Copyright (c) 2026 Jesse Jurman. zlib license - see LICENSE.md
 */

#include "eclair_backend.h"

#if defined(__linux__)

#include <dlfcn.h>
#include <stddef.h> /* NULL */
#include <math.h> /* lroundf */

#define ECLAIR_DLSYM(lib, fn, name) (*(void **)(&(fn)) = dlsym((lib), (name)))

static float g_rate = 0.5f;
static float g_volume = 1.0f;

/* ---------------------------------------------------------------
 * Speech Dispatcher - libspeechd.so.2, resolved at runtime
 * --------------------------------------------------------------- */

typedef struct SPDConnection SPDConnection;

// SPDConnectionMode - SINGLE means libspeechd spawns no reader thread
#define ECLAIR_SPD_MODE_SINGLE 0

// SPDPriority - TEXT is superseded by the next message of any priority
#define ECLAIR_SPD_TEXT 3

typedef SPDConnection *(*PFN_spd_open)(const char *client_name, const char *connection_name, const char *user_name, int mode);

typedef void (*PFN_spd_close)(SPDConnection *conn);
typedef int (*PFN_spd_say)(SPDConnection *conn, int priority, const char *text);
typedef int (*PFN_spd_cancel)(SPDConnection *conn);
typedef int (*PFN_spd_set_voice_rate)(SPDConnection *conn, int rate);
typedef int (*PFN_spd_set_volume)(SPDConnection *conn, int volume);

static void *g_speechd_lib = NULL;
static SPDConnection *g_spd = NULL;

static PFN_spd_open g_spd_open = NULL;
static PFN_spd_close g_spd_close = NULL;
static PFN_spd_say g_spd_say = NULL;
static PFN_spd_cancel g_spd_cancel = NULL;
static PFN_spd_set_voice_rate g_spd_set_voice_rate = NULL;
static PFN_spd_set_volume g_spd_set_volume = NULL;

static void speechd_unload(void) {
	if (g_spd != NULL) {
		g_spd_close(g_spd);
		g_spd = NULL;
	}

	if (g_speechd_lib != NULL) {
		dlclose(g_speechd_lib);
		g_speechd_lib = NULL;
	}

	g_spd_open = NULL;
	g_spd_close = NULL;
	g_spd_say = NULL;
	g_spd_cancel = NULL;
	g_spd_set_voice_rate = NULL;
	g_spd_set_volume = NULL;
}

static void speechd_load(void) {
	// point to versioned soname
	g_speechd_lib = dlopen("libspeechd.so.2", RTLD_LAZY | RTLD_LOCAL);
	if (g_speechd_lib == NULL)
		return;

	ECLAIR_DLSYM(g_speechd_lib, g_spd_open, "spd_open");
	ECLAIR_DLSYM(g_speechd_lib, g_spd_close, "spd_close");
	ECLAIR_DLSYM(g_speechd_lib, g_spd_say, "spd_say");
	ECLAIR_DLSYM(g_speechd_lib, g_spd_cancel, "spd_cancel");
	ECLAIR_DLSYM(g_speechd_lib, g_spd_set_voice_rate, "spd_set_voice_rate");
	ECLAIR_DLSYM(g_speechd_lib, g_spd_set_volume, "spd_set_volume");

	// connect to speech-dispatcher (spawns daemon if it is not running)
	g_spd = g_spd_open("eclair", "eclair", NULL, ECLAIR_SPD_MODE_SINGLE);
}

static bool speechd_available(void) {
	return g_spd != NULL;
}

static bool speechd_speak(const char *utf8, bool interrupt) {
	if (g_spd == NULL)
		return false;

	// cancel clears the queue and current utterance
	if (interrupt)
		g_spd_cancel(g_spd);

	return g_spd_say(g_spd, ECLAIR_SPD_TEXT, utf8) != -1;
}

static bool speechd_stop(void) {
	if (g_spd == NULL)
		return false;

	return g_spd_cancel(g_spd) == 0;
}

static void speechd_set_rate(float rate) {
	g_rate = rate;
	if (g_spd != NULL) {
		// range is -100 to 100, 0 is the default
		int spd_rate = (int) lroundf(eclair_map_rate(rate, -100.0f, 0.0f, 100.0f));
		g_spd_set_voice_rate(g_spd, spd_rate);
	}
}

static void speechd_set_volume(float volume) {
	g_volume = volume;
	if (g_spd != NULL) {
		// range is -100 to 100, 0 is the default
		int spd_volume = (int) lroundf((volume - 1.0f) * 100.0f);
		g_spd_set_volume(g_spd, spd_volume);
	}
}

static const char *speechd_name(void) {
	return "Speech Dispatcher";
}

/* ---------------------------------------------------------------
 * Orca - org.gnome.Orca.Service over libdbus-1
 * --------------------------------------------------------------- */

static void orca_load(void) {}

static void orca_unload(void) {}

static bool orca_available(void) {
	return false;
}

static bool orca_speak(const char *utf8, bool interrupt) {
	(void)utf8;
	(void)interrupt;
	return false;
}

static bool orca_stop(void) {
	return false;
}

static const char *orca_name(void) {
	return "Orca";
}

// lifecycle

bool eclair_platform_init(void) {
	speechd_load();
	orca_load();

	return true;
}

void eclair_platform_shutdown(void) {
	orca_unload();
	speechd_unload();
}

// screen reader lifecycle functions (Orca)

bool eclair_sr_available(void) {
	return orca_available();
}

bool eclair_sr_speak(const char *utf8, bool interrupt) {
	return orca_speak(utf8, interrupt);
}

bool eclair_sr_stop(void) {
	return orca_stop();
}

const char *eclair_sr_name(void) {
	return orca_available() ? orca_name() : NULL;
}

// synthesizer lifecycle functions (Speech Dispatcher)

bool eclair_synth_available(void) {
	return speechd_available();
}

bool eclair_synth_speak(const char *utf8, bool interrupt) {
	return speechd_speak(utf8, interrupt);
}

bool eclair_synth_stop(void) {
	return speechd_stop();
}

void eclair_synth_set_rate(float rate) {
	speechd_set_rate(rate);
}

void eclair_synth_set_volume(float volume) {
	speechd_set_volume(volume);
}

const char *eclair_synth_name(void) {
	return speechd_available() ? speechd_name() : NULL;
}

#else
// not a linux platform
typedef int eclair_linux_unused_translation_unit;
#endif /* __linux__ */
