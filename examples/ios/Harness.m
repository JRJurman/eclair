/*
 * eclair - iOS test harness
 * Copyright (c) 2026 Jesse Jurman. zlib license - see LICENSE.md
 *
 * The same controls the Tk and Android harnesses expose, driving the ten
 * public functions and nothing else. There is no shim: Objective-C calls
 * eclair's C directly, and harness.c exists on Android only because that
 * harness is written in Java. eclair is compiled from source into this app
 * rather than linked, which is the vendoring instruction rather than a
 * prebuilt - and on iOS it is the only mode there is.
 *
 * Everything is drawn on one view and hit-tested by hand, where the other two
 * harnesses use the platform's own widgets. That is not decoration. iOS is
 * the one platform where a UIKit control cannot test the screen reader route
 * at all: with VoiceOver running, every button press is a VoiceOver
 * activation, and an announcement posted inside one is dropped while
 * VoiceOver speaks the control's own label. A game is never in that
 * situation - it draws its own interface and calls eclair from its frame
 * loop - so a widget harness measures the harness rather than the library.
 *
 * SDL_uikitview.m sets no accessibility properties whatsoever, so a host
 * built on it presents one view with no accessibility elements and no traits
 * - and VoiceOver has nothing to pass a touch to. A game that ships
 * accessibility has to say so itself, and a shipping one does it by swizzling
 * SDL_uikitview - isAccessibilityElement, accessibilityTraits and
 * accessibilityDirectTouchOptions all replaced at runtime, since SDL builds
 * the view and there is nothing to subclass. This canvas is its own view, so
 * it sets the same three directly. Launching with -directTouch NO takes them
 * back off, to show what stock SDL costs rather than to be used.
 */

#import <UIKit/UIKit.h>

#include "eclair.h"

#pragma mark - model

typedef NS_ENUM(NSInteger, ControlKind) {
	ControlKindButton,
	ControlKindSegment,
	ControlKindSlider,
};

typedef NS_ENUM(NSInteger, ControlTag) {
	TagSpeak,
	TagSpeakInterrupt,
	TagStop,
	TagText,
	TagRoute,
	TagRate,
	TagVolume,
};

@interface Control : NSObject
@property (nonatomic) CGRect frame;
@property (nonatomic) ControlKind kind;
@property (nonatomic) ControlTag tag;
@property (nonatomic) NSInteger index;   /* which segment, for ControlKindSegment */
@property (nonatomic) BOOL on;
@property (nonatomic, copy) NSString *title;
@end

@implementation Control
@end

/* The other two harnesses let you type. A canvas has no text field, so the
 * same ability to speak different strings arrives as a list to cycle. */
static NSString *const kTexts[] = {
	@"The quick brown fox jumps over the lazy dog.",
	@"Short.",
	@"Tears of joy \U0001F602",
	@"A much longer line, so that interrupt and stop have something running to "
	 "cut into: the quick brown fox jumps over the lazy dog, then turns around "
	 "and jumps back over it again, twice.",
};
static const NSInteger kTextCount = sizeof(kTexts) / sizeof(kTexts[0]);

static NSString *const kRoutes[] = { @"off", @"screen reader", @"prefer", @"synthesizer" };
static const NSInteger kRouteCount = 4;

static NSString *OutputName(eclair_output out) {
	switch (out) {
		case ECLAIR_OUTPUT_NONE:          return @"NONE";
		case ECLAIR_OUTPUT_SCREEN_READER: return @"SCREEN_READER";
		case ECLAIR_OUTPUT_SYNTHESIZER:   return @"SYNTHESIZER";
	}
	return @"?";
}

static NSString *ErrName(eclair_error err) {
	return [NSString stringWithUTF8String:eclair_error_string(err)];
}

#pragma mark - the canvas

@interface CanvasView : UIView
@end

@implementation CanvasView {
	NSMutableArray<Control *> *_controls;
	Control *_tracking;

	NSInteger _textIndex;
	NSInteger _route;
	float _rate;
	float _volume;
	NSString *_status;
	NSString *_result;

	NSTimer *_poll;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self == nil)
		return nil;

	_controls = [NSMutableArray array];
	_textIndex = 0;
	_route = ECLAIR_ROUTE_PREFER_SCREEN_READER;
	_rate = 0.5f;
	_volume = 1.0f;
	_status = @"";
	_result = @"";

	self.backgroundColor = UIColor.systemBackgroundColor;
	self.multipleTouchEnabled = NO;

	/* There are no subviews at all, so without a trait of its own this view is
	 * invisible to VoiceOver and so are the touches meant for it. The trait is
	 * the whole accessibility surface the canvas has, and it is on unless the
	 * launch argument takes it off. */
	NSNumber *setting = [NSUserDefaults.standardUserDefaults objectForKey:@"directTouch"];
	if (setting == nil || setting.boolValue) {
		self.isAccessibilityElement = YES;
		self.accessibilityTraits = UIAccessibilityTraitAllowsDirectInteraction;
		self.accessibilityLabel = @"eclair harness canvas";

		/* The third of those, and the one that matters to eclair rather than
		 * to touch handling: inside a direct-interaction element VoiceOver
		 * still runs its own per-touch processing and speaks, which is another
		 * utterance for an announcement to lose to. SilentOnTouch hands the
		 * touch over and says nothing. iOS 17, so a game below that floor
		 * keeps the competing utterance. */
		if (@available(iOS 17.0, *))
			self.accessibilityDirectTouchOptions = UIAccessibilityDirectTouchOptionSilentOnTouch;
	}

	/* Re-read routing every 500ms, as the other two harnesses do. eclair.h
	 * says a screen reader can start or stop at any time, so this is the
	 * contract made visible - and it stands in for an availability
	 * callback, with no thread anywhere. */
	_poll = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
		(void)t;
		[self refresh];
	}];
	[self refresh];

	return self;
}

- (void)dealloc {
	[_poll invalidate];
}

#pragma mark - layout

/* One pass builds the control list; drawRect: and touch handling both read
 * it, so a rect can never be drawn in one place and hit in another. */
- (void)layoutSubviews {
	[super layoutSubviews];

	[_controls removeAllObjects];

	const CGFloat pad = 20;
	const CGFloat rowH = 46;
	const CGFloat gap = 12;

	CGFloat x = self.safeAreaInsets.left + pad;
	CGFloat w = self.bounds.size.width - x - self.safeAreaInsets.right - pad;
	CGFloat y = self.safeAreaInsets.top + pad;

	y += 22; /* "Text" caption */
	[self add:ControlKindButton tag:TagText index:0 frame:CGRectMake(x, y, w, rowH) title:nil];
	y += rowH + gap;

	CGFloat third = (w - 2 * 8) / 3;
	[self add:ControlKindButton tag:TagSpeak          index:0 frame:CGRectMake(x, y, third, rowH)                    title:@"Speak"];
	[self add:ControlKindButton tag:TagSpeakInterrupt index:0 frame:CGRectMake(x + third + 8, y, third, rowH)        title:@"Interrupt"];
	[self add:ControlKindButton tag:TagStop           index:0 frame:CGRectMake(x + 2 * (third + 8), y, third, rowH)  title:@"Stop"];
	y += rowH + gap;

	y += 22; /* "Route" caption */
	CGFloat seg = (w - 3 * 6) / kRouteCount;
	for (NSInteger i = 0; i < kRouteCount; i++) {
		Control *c = [self add:ControlKindSegment tag:TagRoute index:i
										 frame:CGRectMake(x + i * (seg + 6), y, seg, rowH)
										 title:kRoutes[i]];
		c.on = (i == _route);
	}
	y += rowH + gap;

	y += 22; /* "Rate" caption */
	[self add:ControlKindSlider tag:TagRate index:0 frame:CGRectMake(x, y, w, rowH) title:nil];
	y += rowH + gap;

	y += 22; /* "Volume" caption */
	[self add:ControlKindSlider tag:TagVolume index:0 frame:CGRectMake(x, y, w, rowH) title:nil];
}

- (Control *)add:(ControlKind)kind tag:(ControlTag)tag index:(NSInteger)index
					 frame:(CGRect)frame title:(NSString *)title {
	Control *c = [[Control alloc] init];
	c.kind = kind;
	c.tag = tag;
	c.index = index;
	c.frame = frame;
	c.title = title;
	[_controls addObject:c];
	return c;
}

- (Control *)controlWithTag:(ControlTag)tag {
	for (Control *c in _controls)
		if (c.tag == tag)
			return c;
	return nil;
}

#pragma mark - drawing

- (void)drawRect:(CGRect)rect {
	(void)rect;

	for (Control *c in _controls) {
		switch (c.kind) {
			case ControlKindButton:
				if (c.tag == TagText)
					[self drawBox:c.frame filled:NO text:kTexts[_textIndex] muted:NO];
				else
					[self drawBox:c.frame filled:NO text:c.title muted:NO];
				break;

			case ControlKindSegment:
				[self drawBox:c.frame filled:c.on text:c.title muted:NO];
				break;

			case ControlKindSlider:
				[self drawSlider:c.frame value:(c.tag == TagRate ? _rate : _volume)];
				break;
		}
	}

	/* captions sit just above the control they name */
	[self caption:@"Text"                                            above:[self controlWithTag:TagText]];
	[self caption:@"Route"                                           above:[self controlWithTag:TagRoute]];
	[self caption:[NSString stringWithFormat:@"Rate %.2f", _rate]    above:[self controlWithTag:TagRate]];
	[self caption:[NSString stringWithFormat:@"Volume %.2f", _volume] above:[self controlWithTag:TagVolume]];

	Control *last = [self controlWithTag:TagVolume];
	CGFloat y = CGRectGetMaxY(last.frame) + 24;
	CGFloat x = last.frame.origin.x;
	CGFloat w = last.frame.size.width;

	[UIColor.separatorColor setFill];
	UIRectFill(CGRectMake(x, y, w, 1));
	y += 16;

	[self text:_status at:CGRectMake(x, y, w, 40) mono:YES muted:YES];
	y += 22;
	[self text:_result at:CGRectMake(x, y, w, 40) mono:YES muted:NO];
}

- (void)drawBox:(CGRect)frame filled:(BOOL)filled text:(NSString *)text muted:(BOOL)muted {
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:8];

	if (filled) {
		[UIColor.systemBlueColor setFill];
		[path fill];
	} else {
		[UIColor.separatorColor setStroke];
		path.lineWidth = 1;
		[path stroke];
	}

	UIColor *color = filled ? UIColor.whiteColor
													: (muted ? UIColor.secondaryLabelColor : UIColor.systemBlueColor);
	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
	style.alignment = NSTextAlignmentCenter;
	style.lineBreakMode = NSLineBreakByTruncatingTail;

	UIFont *font = [UIFont systemFontOfSize:15];
	CGFloat h = font.lineHeight;
	[text drawInRect:CGRectMake(frame.origin.x + 6,
															frame.origin.y + (frame.size.height - h) / 2,
															frame.size.width - 12, h)
		withAttributes:@{ NSFontAttributeName: font,
											NSForegroundColorAttributeName: color,
											NSParagraphStyleAttributeName: style }];
}

- (void)drawSlider:(CGRect)frame value:(float)value {
	CGFloat mid = CGRectGetMidY(frame);
	CGRect track = CGRectMake(frame.origin.x, mid - 2, frame.size.width, 4);

	[UIColor.separatorColor setFill];
	[[UIBezierPath bezierPathWithRoundedRect:track cornerRadius:2] fill];

	CGRect done = CGRectMake(track.origin.x, track.origin.y, track.size.width * value, track.size.height);
	[UIColor.systemBlueColor setFill];
	[[UIBezierPath bezierPathWithRoundedRect:done cornerRadius:2] fill];

	CGFloat knob = 24;
	CGRect k = CGRectMake(frame.origin.x + frame.size.width * value - knob / 2, mid - knob / 2, knob, knob);
	[UIColor.systemBlueColor setFill];
	[[UIBezierPath bezierPathWithOvalInRect:k] fill];
}

- (void)caption:(NSString *)text above:(Control *)control {
	[self text:text
					at:CGRectMake(control.frame.origin.x, control.frame.origin.y - 22, control.frame.size.width, 20)
				mono:NO
			 muted:NO];
}

- (void)text:(NSString *)text at:(CGRect)frame mono:(BOOL)mono muted:(BOOL)muted {
	UIFont *font = mono ? [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]
											: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	[text drawInRect:frame
		withAttributes:@{ NSFontAttributeName: font,
											NSForegroundColorAttributeName: muted ? UIColor.secondaryLabelColor
																																		: UIColor.labelColor }];
}

#pragma mark - touch

- (Control *)hitTestControl:(CGPoint)point {
	for (Control *c in _controls) {
		CGRect slop = (c.kind == ControlKindSlider) ? CGRectInset(c.frame, 0, -10) : c.frame;
		if (CGRectContainsPoint(slop, point))
			return c;
	}
	return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	(void)event;

	CGPoint p = [touches.anyObject locationInView:self];
	_tracking = [self hitTestControl:p];

	if (_tracking.kind == ControlKindSlider)
		[self dragSlider:_tracking to:p];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	(void)event;

	if (_tracking.kind != ControlKindSlider)
		return;

	[self dragSlider:_tracking to:[touches.anyObject locationInView:self]];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	(void)event;

	Control *c = _tracking;
	_tracking = nil;

	if (c == nil || c.kind == ControlKindSlider)
		return;

	CGPoint p = [touches.anyObject locationInView:self];
	if (!CGRectContainsPoint(c.frame, p))
		return;

	[self activate:c];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	(void)touches;
	(void)event;
	_tracking = nil;
}

- (void)dragSlider:(Control *)c to:(CGPoint)p {
	float v = (float)((p.x - c.frame.origin.x) / c.frame.size.width);
	v = v < 0 ? 0 : (v > 1 ? 1 : v);

	if (c.tag == TagRate) {
		_rate = v;
		eclair_set_rate(v);
	} else {
		_volume = v;
		eclair_set_volume(v);
	}

	[self setNeedsDisplay];
}

#pragma mark - driving eclair

- (void)activate:(Control *)c {
	switch (c.tag) {
		case TagText:
			_textIndex = (_textIndex + 1) % kTextCount;
			break;

		case TagSpeak:
			[self report:@"speak" code:eclair_speak(kTexts[_textIndex].UTF8String, false)];
			break;

		case TagSpeakInterrupt:
			[self report:@"speak(interrupt)" code:eclair_speak(kTexts[_textIndex].UTF8String, true)];
			break;

		case TagStop:
			[self report:@"stop" code:eclair_stop()];
			break;

		case TagRoute:
			_route = c.index;
			eclair_set_route((eclair_route)_route);
			[self setNeedsLayout];
			[self refresh];
			break;

		default:
			break;
	}

	[self setNeedsDisplay];
}

- (void)report:(NSString *)call code:(eclair_error)code {
	_result = [NSString stringWithFormat:@"%@ -> %@", call, ErrName(code)];
	[self setNeedsDisplay];
}

- (void)refresh {
	const char *name = eclair_backend_name();

	_status = [NSString stringWithFormat:@"output = %@    backend = %@",
		OutputName(eclair_current_output()),
		name ? [NSString stringWithUTF8String:name] : @"(none)"];

	[self setNeedsDisplay];
}

@end

#pragma mark - app delegate

@interface HarnessAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HarnessAppDelegate

- (BOOL)application:(UIApplication *)application
		didFinishLaunchingWithOptions:(NSDictionary *)options {
	(void)application;
	(void)options;

	eclair_error err = eclair_init();

	UIViewController *vc = [[UIViewController alloc] init];
	vc.view = [[CanvasView alloc] initWithFrame:UIScreen.mainScreen.bounds];

	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.window.rootViewController = vc;
	[self.window makeKeyAndVisible];

	NSLog(@"eclair_init -> %@", ErrName(err));
	return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application {
	(void)application;
	eclair_shutdown();
}

@end

int main(int argc, char *argv[]) {
	@autoreleasepool {
		return UIApplicationMain(argc, argv, nil, NSStringFromClass(HarnessAppDelegate.class));
	}
}
