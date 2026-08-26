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
#include <objbase.h> /* CoInitializeEx */
#include <sapi.h>
#include <stddef.h> /* NULL */
#include <stdlib.h>

/* true when our CoInitializeEx call was counted and we owe a CoUninitialize */
static bool g_com_owned = false;

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

static bool nvda_available(void) {
	// 0 is success, anything else means NVDA is not running
	return g_nvda_test_if_running != NULL && g_nvda_test_if_running() == 0;
}

static bool nvda_speak(const char *utf8, bool interrupt) {
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

static bool nvda_stop(void) {
	if (g_nvda_cancel_speech == NULL)
		return false;

	return g_nvda_cancel_speech() == 0;
}

// screen reader backends supported by windows;
// we will pick the first available one - we only expect one to be active at a time

typedef struct {
	const char *name;
	bool (*available)(void);
	bool (*speak)(const char *utf8, bool interrupt);
	bool (*stop)(void);
} eclair_sr_backend;

static const eclair_sr_backend g_sr_backends[] = {
	{ "NVDA", nvda_available, nvda_speak, nvda_stop },
};

static const eclair_sr_backend *sr_active(void) {
	size_t count = sizeof(g_sr_backends) / sizeof(g_sr_backends[0]);

	// as soon as we find an available screen reader, return it
	for (size_t i = 0; i < count; i++) {
		if (g_sr_backends[i].available()) {
			return &g_sr_backends[i];
		}
	}

	// could not find an available screen reader
	return NULL;
}

// SAPI - windows synthesizer that is always present

static ISpVoice *g_voice = NULL;

static void sapi_unload(void) {
	if (g_voice != NULL) {
		g_voice->Release();
		g_voice = NULL;
	}
}

static void sapi_load(void) {
	HRESULT hr = CoCreateInstance(CLSID_SpVoice, NULL, CLSCTX_ALL,
																IID_ISpVoice, (void **)&g_voice);

	if (FAILED(hr))
		g_voice = NULL;
}

// lifecycle

bool eclair_platform_init(void) {
	HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);

	/* S_OK - we initialized it (we'll need to uninitialize),
	 * S_FALSE - already initialized (still need to uninitialize),
	 * RPC_E_CHANGED_MODE - host chose the other apartment (no need to uninitialize)
	 */
	if (hr == RPC_E_CHANGED_MODE) {
		g_com_owned = false;
	} else if (SUCCEEDED(hr)) {
		g_com_owned = true;
	} else {
		// resource failure
		return false;
	}

	sapi_load();
	nvda_load();
	return true;
}

void eclair_platform_shutdown(void) {
	nvda_unload();
	sapi_unload();

	if (g_com_owned) {
		CoUninitialize();
		g_com_owned = false;
	}
}

// screen readers - NVDA, JAWS, UIA

bool eclair_sr_available(void) {
	return sr_active() != NULL;
}

bool eclair_sr_speak(const char *utf8, bool interrupt) {
	const eclair_sr_backend *sr = sr_active();
	return sr != NULL && sr->speak(utf8, interrupt);
}

bool eclair_sr_stop(void) {
	const eclair_sr_backend *sr = sr_active();
	return sr != NULL && sr->stop();
}

const char *eclair_sr_name(void) {
	const eclair_sr_backend *sr = sr_active();
	return sr != NULL ? sr->name : NULL;
}

// synthesizer - SAPI

bool eclair_synth_available(void) {
	return g_voice != NULL;
}

bool eclair_synth_speak(const char *utf8, bool interrupt) {
	if (g_voice == NULL)
		return false;

	wchar_t *wide = utf8_to_wide(utf8);
	if (wide == NULL)
		return false;

	/* ASYNC, otherwise Speak() will block until utterance finishes;
	 * NOT_XML, otherwise SAPI parses text with "<" as XML
	 */
	DWORD flags = SPF_ASYNC | SPF_IS_NOT_XML;
	if (interrupt)
		flags |= SPF_PURGEBEFORESPEAK;

	HRESULT hr = g_voice->Speak(wide, flags, NULL);

	free(wide);
	return SUCCEEDED(hr);
}

bool eclair_synth_stop(void) {
	if (g_voice == NULL)
		return false;

	// NULL is documented as a way to stop current utterance
	HRESULT hr = g_voice->Speak(NULL, SPF_PURGEBEFORESPEAK, NULL);
	return SUCCEEDED(hr);
}

void eclair_synth_set_rate(float rate) {
	g_rate = rate;
	if (g_voice != NULL) {
		long sapi_rate = (long) eclair_map_rate(rate, -10.0f, 0.0f, 10.0f);
		g_voice->SetRate(sapi_rate);
	}
}

void eclair_synth_set_volume(float volume) {
	g_volume = volume;
	if (g_voice != NULL) {
		USHORT sapi_volume = (USHORT) (volume * 100.0f);
		g_voice->SetVolume(sapi_volume);
	}

}

const char *eclair_synth_name(void) {
	return g_voice != NULL ? "SAPI" : NULL;
}


#else
// Not a windows platform
typedef int eclair_window_unused_translation_unit;
#endif /* _WIN32 */
