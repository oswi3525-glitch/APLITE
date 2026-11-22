#import "GuestRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach/mach_time.h>

// Synthetic touches through private UIKit API (the same technique UI testing tools use):
// build a UITouch, attach a fake IOHIDEvent and send it straight to the guest app's window.

typedef struct __IOHIDEvent *IOHIDEventRef;

@interface UITouch (iDeskPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setTapCount:(NSUInteger)tapCount;
- (void)setIsTap:(BOOL)isTap;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)phase;
- (void)setGestureView:(UIView *)view;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)_setIsFirstTouchForView:(BOOL)first;
- (void)_setIsTapToClick:(BOOL)tapToClick;
- (void)_setHidEvent:(IOHIDEventRef)event;
@end

@interface UIEvent (iDeskPrivate)
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_clearTouches;
- (void)_setHIDEvent:(IOHIDEventRef)event;
@end

@interface UIApplication (iDeskPrivate)
- (UIEvent *)_touchesEvent;
@end

@interface UIWindow (iDeskPrivate)
- (UIResponder *)firstResponder;
@end

extern BOOL GuestSyntheticHitTest;

static UIEvent *TouchesEvent(void);

/// Finds the view under the touch; only now does the guest window answer hitTest (see GuestRuntime.m).
/// A touch-type event must be passed: with a nil event, SwiftUI views (and UIKit sheets) treat it as
/// not a touch and let it pass through.
UIView *GuestTouchHitTest(UIWindow *window, CGPoint point) {
    GuestSyntheticHitTest = YES;
    UIView *view = [window hitTest:point withEvent:TouchesEvent()];
    GuestSyntheticHitTest = NO;
    return view;
}

// MARK: - Fake IOHIDEvent

enum {
    kHIDTransducerHand = 3,
    kHIDTransducerFinger = 2,
    kHIDEventRange = 1 << 0,
    kHIDEventTouch = 1 << 1,
    kHIDEventPosition = 1 << 2,
    kHIDFieldIsBuiltIn = 0x4,
    kHIDFieldDisplayIntegrated = 0xB0019,
};

static IOHIDEventRef CreateHIDEvent(CGPoint point, UITouchPhase phase) {
    typedef IOHIDEventRef (*CreateDigitizer)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t,
                                             double, double, double, double, double, Boolean, Boolean, uint32_t);
    typedef IOHIDEventRef (*CreateFinger)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
                                          double, double, double, double, double, Boolean, Boolean, uint32_t);
    typedef void (*SetInteger)(IOHIDEventRef, uint32_t, long, uint32_t);
    typedef void (*Append)(IOHIDEventRef, IOHIDEventRef, uint32_t);

    static CreateDigitizer createDigitizer;
    static CreateFinger createFinger;
    static SetInteger setInteger;
    static Append append;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        createDigitizer = (CreateDigitizer)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
        createFinger = (CreateFinger)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEvent");
        setInteger = (SetInteger)dlsym(RTLD_DEFAULT, "IOHIDEventSetIntegerValueWithOptions");
        append = (Append)dlsym(RTLD_DEFAULT, "IOHIDEventAppendEvent");
    });
    if (!createDigitizer || !createFinger || !setInteger || !append) return NULL;

    uint64_t now = mach_absolute_time();
    BOOL touching = phase != UITouchPhaseEnded && phase != UITouchPhaseCancelled;
    uint32_t mask = phase == UITouchPhaseMoved ? kHIDEventPosition : (kHIDEventRange | kHIDEventTouch);

    IOHIDEventRef hand = createDigitizer(kCFAllocatorDefault, now, kHIDTransducerHand, 0, 0, kHIDEventTouch, 0,
                                         0, 0, 0, 0, 0, false, true, 0);
    setInteger(hand, kHIDFieldDisplayIntegrated, 1, 0xF0000000);
    setInteger(hand, kHIDFieldIsBuiltIn, 1, 0xF0000000);
    IOHIDEventRef finger = createFinger(kCFAllocatorDefault, now, 1, kHIDTransducerFinger, mask,
                                        point.x, point.y, 0, 0, 0, touching, touching, 0);
    setInteger(finger, kHIDFieldDisplayIntegrated, 1, 0xF0000000);
    append(hand, finger, 0);
    CFRelease(finger);
    return hand;
}

// MARK: - Touches

static UITouch *gTouch;
static UIWindow *gTouchWindow;
static UIEvent *gEvent;

static UIEvent *TouchesEvent(void) {
    // Use a separate event so the real finger on the iPhone trackpad is left alone.
    if (!gEvent) {
        Class cls = NSClassFromString(@"UITouchesEvent");
        SEL sel = NSSelectorFromString(@"_init");
        if (cls && [cls instancesRespondToSelector:sel]) {
            gEvent = ((id (*)(id, SEL))objc_msgSend)([cls alloc], sel);
        }
        if (!gEvent) gEvent = [UIApplication.sharedApplication _touchesEvent];
    }
    return gEvent;
}

static void Deliver(UITouch *touch, UIWindow *window, CGPoint point) {
    IOHIDEventRef hid = CreateHIDEvent(point, touch.phase);
    if (hid && [touch respondsToSelector:@selector(_setHidEvent:)]) [touch _setHidEvent:hid];

    UIEvent *event = TouchesEvent();
    if (hid && [event respondsToSelector:@selector(_setHIDEvent:)]) [event _setHIDEvent:hid];
    if (touch.phase == UITouchPhaseBegan) {
        // Register the finger with the event once, at touch down; later phases only update the UITouch.
        [event _clearTouches];
        [event _addTouch:touch forDelayedDelivery:NO];
    }
    GuestSyntheticHitTest = YES;      // in case UIKit hit-tests again while dispatching
    [window sendEvent:event];
    GuestSyntheticHitTest = NO;
    if (hid) CFRelease((CFTypeRef)hid);
}

@implementation GuestTouch

+ (BOOL)isActive { return gTouch != nil; }

+ (void)beginAt:(CGPoint)point inWindow:(UIWindow *)window {
    if (gTouch) [self end];       // rapid clicks: finish the previous touch before starting a new one
    UIView *view = GuestTouchHitTest(window, point);
    if (!view) return;

    UITouch *touch = [[UITouch alloc] init];
    [touch setWindow:window];     // must be called first, it resets the other values
    [touch _setLocationInWindow:point resetPrevious:YES];
    [touch setView:view];
    [touch setTapCount:1];
    [touch setPhase:UITouchPhaseBegan];
    if ([touch respondsToSelector:@selector(_setIsTapToClick:)]) [touch _setIsTapToClick:NO];
    if ([touch respondsToSelector:@selector(_setIsFirstTouchForView:)]) [touch _setIsFirstTouchForView:YES];
    if ([touch respondsToSelector:@selector(setIsTap:)]) [touch setIsTap:NO];
    [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    if ([touch respondsToSelector:@selector(setGestureView:)]) [touch setGestureView:view];

    gTouch = touch;
    gTouchWindow = window;
    Deliver(touch, window, point);
}

+ (void)moveTo:(CGPoint)point {
    if (!gTouch) return;
    [gTouch _setLocationInWindow:point resetPrevious:NO];
    [gTouch setPhase:UITouchPhaseMoved];
    [gTouch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    Deliver(gTouch, gTouchWindow, point);
}

+ (void)finishWithPhase:(UITouchPhase)phase {
    if (!gTouch) return;
    UITouch *touch = gTouch;
    UIWindow *window = gTouchWindow;
    gTouch = nil;
    gTouchWindow = nil;
    [touch setPhase:phase];
    [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    Deliver(touch, window, [touch locationInView:window]);
}

+ (void)end { [self finishWithPhase:UITouchPhaseEnded]; }
+ (void)cancel { [self finishWithPhase:UITouchPhaseCancelled]; }

// MARK: Scrolling

+ (BOOL)scrollAt:(CGPoint)point inWindow:(UIWindow *)window dx:(CGFloat)dx dy:(CGFloat)dy {
    for (UIView *view = GuestTouchHitTest(window, point); view; view = view.superview) {
        if (![view isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *scroll = (UIScrollView *)view;
        if (!scroll.isScrollEnabled) continue;
        UIEdgeInsets inset = scroll.adjustedContentInset;
        CGFloat minX = -inset.left, minY = -inset.top;
        CGFloat maxX = MAX(minX, scroll.contentSize.width + inset.right - scroll.bounds.size.width);
        CGFloat maxY = MAX(minY, scroll.contentSize.height + inset.bottom - scroll.bounds.size.height);
        CGPoint offset = scroll.contentOffset;
        CGPoint target = CGPointMake(MIN(MAX(offset.x + dx, minX), maxX), MIN(MAX(offset.y + dy, minY), maxY));
        if (CGPointEqualToPoint(target, offset)) continue;   // reached the end: try the enclosing scroll view
        scroll.contentOffset = target;
        return YES;
    }
    return NO;
}

// MARK: Keyboard

+ (id<UIKeyInput>)keyInputInWindow:(UIWindow *)window {
    if (![window respondsToSelector:@selector(firstResponder)]) return nil;
    UIResponder *responder = [window firstResponder];
    return [responder conformsToProtocol:@protocol(UIKeyInput)] ? (id<UIKeyInput>)responder : nil;
}

+ (BOOL)insertText:(NSString *)text inWindow:(UIWindow *)window {
    id<UIKeyInput> input = [self keyInputInWindow:window];
    if (!input) return NO;
    if ([text isEqualToString:@"\n"] && [input isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)input;
        BOOL shouldReturn = YES;
        if ([field.delegate respondsToSelector:@selector(textFieldShouldReturn:)]) {
            shouldReturn = [field.delegate textFieldShouldReturn:field];
        }
        if (shouldReturn) [field sendActionsForControlEvents:UIControlEventEditingDidEndOnExit];
        return YES;
    }
    [input insertText:text];
    return YES;
}

+ (BOOL)performEditAction:(SEL)action inWindow:(UIWindow *)window {
    if (![window respondsToSelector:@selector(firstResponder)]) return NO;
    UIResponder *responder = [window firstResponder];
    // The text view itself, or whatever up the chain handles it (a web view, a custom editor…).
    UIResponder *target = [responder targetForAction:action withSender:nil];
    if (!target) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(target, action, nil);
    return YES;
}

+ (BOOL)deleteBackwardInWindow:(UIWindow *)window {
    id<UIKeyInput> input = [self keyInputInWindow:window];
    if (!input) return NO;
    [input deleteBackward];
    return YES;
}

@end
