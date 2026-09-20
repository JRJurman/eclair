/*
 * eclair - Android test harness, JNI shim
 * Copyright (c) 2026 Jesse Jurman. zlib license - see LICENSE.md
 *
 * A host embedding eclair calls eclair_speak() from its own C - this
 * shim exists only because the harness happens to be written in Java.
 */

#include <jni.h>
#include <stdlib.h>
#include <string.h>

#include "eclair.h"

/* Every function here is reached by name. JNI derives the symbol from the
 * fully-qualified Java method - package, class, method, underscores for dots -
 * so renaming HarnessActivity or moving it to another package silently breaks
 * the link at first call with an UnsatisfiedLinkError, not at build time.
 */

JNIEXPORT jint JNICALL
Java_org_eclair_harness_HarnessActivity_init(JNIEnv *env, jclass cls) {
	(void) env;
	(void) cls;

	return (jint) eclair_init();
}

JNIEXPORT void JNICALL
Java_org_eclair_harness_HarnessActivity_shutdown(JNIEnv *env, jclass cls) {
	(void) env;
	(void) cls;

	eclair_shutdown();
}

JNIEXPORT jint JNICALL
Java_org_eclair_harness_HarnessActivity_speak(JNIEnv *env, jclass cls, jbyteArray utf8, jboolean interrupt) {
	jsize len;
	char *buf;
	jint rc;

	(void) cls;

	if (utf8 == NULL)
		return (jint) ECLAIR_ERR_INVALID_ARG;

	len = (*env)->GetArrayLength(env, utf8);

	buf = (char *) malloc((size_t) len + 1);
	if (buf == NULL)
		return (jint) ECLAIR_ERR_BACKEND_FAILED;

	(*env)->GetByteArrayRegion(env, utf8, 0, len, (jbyte *) buf);
	buf[len] = '\0';

	rc = (jint) eclair_speak(buf, interrupt == JNI_TRUE);

	free(buf);
	return rc;
}

JNIEXPORT jint JNICALL
Java_org_eclair_harness_HarnessActivity_stop(JNIEnv *env, jclass cls) {
	(void) env;
	(void) cls;

	return (jint) eclair_stop();
}

JNIEXPORT void JNICALL
Java_org_eclair_harness_HarnessActivity_setRoute(JNIEnv *env, jclass cls, jint route) {
	(void) env;
	(void) cls;

	eclair_set_route((eclair_route) route);
}

JNIEXPORT void JNICALL
Java_org_eclair_harness_HarnessActivity_setRate(JNIEnv *env, jclass cls, jfloat rate) {
	(void) env;
	(void) cls;

	eclair_set_rate((float) rate);
}

JNIEXPORT void JNICALL
Java_org_eclair_harness_HarnessActivity_setVolume(JNIEnv *env, jclass cls, jfloat volume) {
	(void) env;
	(void) cls;

	eclair_set_volume((float) volume);
}

JNIEXPORT jint JNICALL
Java_org_eclair_harness_HarnessActivity_currentOutput(JNIEnv *env, jclass cls) {
	(void) env;
	(void) cls;

	return (jint) eclair_current_output();
}

JNIEXPORT jstring JNICALL
Java_org_eclair_harness_HarnessActivity_backendName(JNIEnv *env, jclass cls) {
	const char *name = eclair_backend_name();

	(void) cls;

	/* NULL is how eclair_backend_name() says there is no backend, and it
	 * crosses as a Java null rather than an empty string - the distinction the
	 * web harness loses, since cwrap's 'string' return turns a NULL pointer
	 * into "". */
	if (name == NULL)
		return NULL;

	/* NewStringUTF is safe here and nowhere else in this file: backend names
	 * are ASCII literals from a closed in-tree set ("TalkBack", "Android
	 * TTS"), so modified UTF-8 and UTF-8 are the same bytes. Announcement text
	 * comes from a player and gets the byte[] treatment above. */
	return (*env)->NewStringUTF(env, name);
}

JNIEXPORT jstring JNICALL
Java_org_eclair_harness_HarnessActivity_errorString(JNIEnv *env, jclass cls, jint err) {
	(void) cls;

	/* eclair_error_string() never returns NULL - it answers "unknown error"
	 * for a value outside the enum. */
	return (*env)->NewStringUTF(env, eclair_error_string((eclair_error) err));
}
