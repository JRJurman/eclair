/*
 * eclair - Windows backend: NVDA, JAWS, UIA (screen readers), SAPI (synthesizer)
 * Copyright (c) 2026 Jesse Jurman. zlib license - see LICENSE.md
 */

#include "eclair_backend.h"

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#include <stddef.h> /* NULL */
#include <stdlib.h>

static float g_rate = 0.5f;
static float g_volume = 1.0f;

static wchar_t *utf8_to_wide(const char *utf8) {
	int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, NULL, 0);
	if (count <= 0)
		return NULL;

	wchar_t *wide = (wchar_t *)malloc((size_t)count * sizeof(wchar_t));
	if (wide == NULL)
		return NULL;

	if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, wide, count) != count) {
		free(wide);
		return NULL;
	}

	return wide;
}

// NVDA - nvdaControllerClient.dll, resolved at runtime;
/* entry points return error_status_t (unsigned long), 0 on success */
typedef unsigned long (WINAPI *PFN_nvda_test_if_running)(void);
typedef unsigned long (WINAPI *PFN_nvda_speak_text)(const wchar_t *text);
typedef unsigned long (WINAPI *PFN_nvda_cancel_speech)(void);
typedef unsigned long (WINAPI *PFN_nvda_braille_message)(const wchar_t *message);

static HMODULE g_nvda_dll = NULL;

static PFN_nvda_test_if_running g_nvda_test_if_running = NULL;
static PFN_nvda_speak_text 			g_nvda_speak_text = NULL;
static PFN_nvda_cancel_speech		g_nvda_cancel_speech = NULL;
static PFN_nvda_braille_message	g_nvda_braille_message = NULL;

static void nvda_unload(void) {
	if (g_nvda_dll != NULL) {
		FreeLibrary(g_nvda_dll);
		g_nvda_dll = NULL;
	}

	g_nvda_test_if_running = NULL;
	g_nvda_speak_text = NULL;
	g_nvda_cancel_speech = NULL;
	g_nvda_braille_message = NULL;
}

static void nvda_load(void) {
	g_nvda_dll = LoadLibraryW(L"nvdaControllerClient.dll");
	if (g_nvda_dll == NULL)
		return;

	g_nvda_test_if_running = reinterpret_cast<PFN_nvda_test_if_running>(
		GetProcAddress(g_nvda_dll, "nvdaController_testIfRunning"));
	g_nvda_speak_text = reinterpret_cast<PFN_nvda_speak_text>(
		GetProcAddress(g_nvda_dll, "nvdaController_speakText"));
	g_nvda_cancel_speech = reinterpret_cast<PFN_nvda_cancel_speech>(
		GetProcAddress(g_nvda_dll, "nvdaController_cancelSpeech"));
	g_nvda_braille_message = reinterpret_cast<PFN_nvda_braille_message>(
		GetProcAddress(g_nvda_dll, "nvdaController_brailleMessage"));

	if (g_nvda_test_if_running == NULL || g_nvda_speak_text == NULL ||
			g_nvda_cancel_speech == NULL || g_nvda_braille_message == NULL)
			nvda_unload();
}

// lifecycle

bool eclair_platform_init(void) {
	nvda_load();
	return true;
}

void eclair_platform_shutdown(void) {
	nvda_unload();
}

// screen readers - NVDA, JAWS, UIA

bool eclair_sr_available(void) {
	// 0 is success; anything else means NVDA is not running
	return g_nvda_test_if_running != NULL && g_nvda_test_if_running() == 0;
}

bool eclair_sr_speak(const char *utf8, bool interrupt) {
	if (g_nvda_speak_text == NULL)
		return false;

	wchar_t *wide = utf8_to_wide(utf8);
	if (wide == NULL)
		return false;

	// if we are interrupting, cancel the current utterance
	if (interrupt)
		g_nvda_cancel_speech();

	bool spoke = g_nvda_speak_text(wide) == 0;
	bool brailled = g_nvda_braille_message(wide) == 0;

	free(wide);
	return spoke || brailled;
}

bool eclair_sr_stop(void) {
	if (g_nvda_cancel_speech == NULL)
		return false;

	return g_nvda_cancel_speech() == 0;
}

const char *eclair_sr_name(void) {
	return eclair_sr_available() ? "NVDA" : NULL;
}

// synthesizer - SAPI

bool eclair_synth_available(void) {
	return false;
}

bool eclair_synth_speak(const char *utf8, bool interrupt) {
	(void)utf8;
	(void)interrupt;
	return false;
}

bool eclair_synth_stop(void) {
	return false;
}

void eclair_synth_set_rate(float rate) {
	g_rate = rate;
}

void eclair_synth_set_volume(float volume) {
	g_volume = volume;
}

const char *eclair_synth_name(void) {
	return NULL;
}


#else
// Not a windows platform
typedef int eclair_awindow_unused_translation_unit;
#endif /* _WIN32 */
