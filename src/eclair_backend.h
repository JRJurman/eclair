/*
 * eclair - internal backend contract
 * Copyright (c) 2026 Jesse Jurman. zlib license - see LICENSE.md
 *
 * platform files should implement the functions below
 */

#ifndef ECLAIR_BACKEND_H
#define ECLAIR_BACKEND_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* called from eclair_init() / eclair_shutdown();
 * init returns false if platform could not start
 */
bool eclair_platform_init(void);
void eclair_platform_shutdown(void);

/* user's assistive technology */
bool eclair_sr_available(void);
bool eclair_sr_speak(const char *utf8, bool interrupt);
bool eclair_sr_stop(void);
const char *eclair_sr_name(void);

/* speech synthesizer eclair drives itself */
bool eclair_synth_available(void);
bool eclair_synth_speak(const char *utf8, bool interrupt);
bool eclair_synth_stop(void);
void eclair_synth_set_rate(float rate);
void eclair_synth_set_volume(float volume);
const char *eclair_synth_name(void);

/* ------------------------------------------------- *
 * Helpers for backend authors, not part of contract
 * ------------------------------------------------- */

/* map eclair's normalized 0-1 rate into a backend native scale;
 * implemented using a linear interpolation function
 */
static inline float eclair_map_rate(float rate, float min, float mid, float max) {
	if (rate < 0.5f)
		return min + (rate / 0.5f) * (mid - min);

	return mid + ((rate - 0.5f) / 0.5f) * (max - mid);
}

#ifdef __cplusplus
}
#endif

#endif /* ECLAIR_BACKEND_H */
