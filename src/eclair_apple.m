/*
 * eclair - Apple backend: VoiceOver (screen reader), AVSpeech (synthesizer)
 * Copyright (c) 2026 Jesse Jurman. zlib license - see LICENSE.md
 */

#include "eclair_backend.h"

#if defined(__APPLE__)

#if !__has_feature(objc_arc)
#error "eclair_apple.m must be compiled with -fobjc-arc"
#endif

#import <TargetConditionals.h>
#import <AVFoundation/AVFoundation.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

static AVSpeechSynthesizer *g_synth = nil;
static float g_rate = 0.5f;
static float g_volume = 1.0f;

bool eclair_platform_init(void) {
	g_synth = [[AVSpeechSynthesizer alloc] init];
	return g_synth != nil;
}

void eclair_platform_shutdown(void) {
	if (g_synth != nil) {
		[g_synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
		g_synth = nil;
	}
}

// VoiceOver

bool eclair_sr_available(void) {
#if TARGET_OS_OSX
		// depends on a running NSApp, so report false if we're not running in one
		if (NSApp == nil)
			return false;
		return [[NSWorkspace sharedWorkspace] isVoiceOverEnabled];
#else
		return UIAccessibilityIsVoiceOverRunning();
#endif
}

bool eclair_sr_speak(const char *utf8, bool interrupt) {
	NSString *msg = [NSString stringWithUTF8String:utf8];
	if (msg == nil)
		return false;

#if TARGET_OS_OSX
	if (NSApp == nil)
		return false;

	// VoiceOver's high priority indicates we should interrupt text
	NSAccessibilityPriorityLevel priority = interrupt ? NSAccessibilityPriorityHigh : NSAccessibilityPriorityMedium;

	NSAccessibilityPostNotificationWithUserInfo(
		NSApp,
		NSAccessibilityAnnouncementRequestedNotification,
		@{ NSAccessibilityAnnouncementKey : msg,
			 NSAccessibilityPriorityKey			: @(priority)});
	return true;
#else
	// UIKit exposes no priority
	(void)interrupt;
	UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, msg);
	return true;
#endif
}

bool eclair_sr_stop(void) {
	// VoiceOver exposes no cancel, so no-op here
	return true;
}

const char *eclair_sr_name(void) {
	return eclair_sr_available() ? "VoiceOver" : NULL;
}

// AVSpeech
bool eclair_synth_available(void) {
	return g_synth != nil;
}

bool eclair_synth_speak(const char *utf8, bool interrupt) {
	if (g_synth == nil)
		return false;

	NSString *text = [NSString stringWithUTF8String:utf8];
	if (text == nil)
		return false;

	if (interrupt)
		[g_synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];

	AVSpeechUtterance *u = [[AVSpeechUtterance alloc] initWithString:text];
	u.rate = eclair_map_rate(g_rate, AVSpeechUtteranceMinimumSpeechRate,
																	 AVSpeechUtteranceDefaultSpeechRate,
																	 AVSpeechUtteranceMaximumSpeechRate);
	u.volume = g_volume;

	[g_synth speakUtterance:u];
	return true;
}

bool eclair_synth_stop(void) {
	if (g_synth == nil)
		return false;

	[g_synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
	return true;
}

void eclair_synth_set_rate(float rate) {
	g_rate = rate;
}

void eclair_synth_set_volume(float volume) {
	g_volume = volume;
}

const char *eclair_synth_name(void) {
	return g_synth != nil ? "AVSpeechSynthesizer" : NULL;
}

#else
// Not an Apple platform
typedef int eclair_apple_unused_translation_unit;
#endif /* __APPLE__ */
