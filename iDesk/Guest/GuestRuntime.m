#import "GuestRuntime.h"
#import "CategoryRepair.h"
#import "GuestShims.h"
#import <objc/runtime.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <crt_externs.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/getsect.h>

UIView *GuestTouchHitTest(UIWindow *window, CGPoint point);

/// One running guest app.
@interface GuestAppRecord : NSObject
@property (nonatomic) int shimID;                   // id in GuestShims
@property (nonatomic, copy) NSString *bundlePath;
@property (nonatomic) NSBundle *bundle;
@property (nonatomic) id appDelegate;               // UIApplication.delegate is weak, so keep a strong reference
@property (nonatomic) id sceneDelegate;
@property (nonatomic) UIWindow *handle;             // identifies the app to iDesk; never shown
@property (nonatomic) UIWindow *window;             // the app's main window (the last one it made key), if any
@property (nonatomic) BOOL suspended;               // its desktop window is closed
@property (nonatomic) NSInteger requestedOrientation; // last rotation the app asked for (see Orientation)
@property (nonatomic) NSHashTable<UIWindow *> *windows;
@property (nonatomic, weak) UIWindowScene *scene;
@property (nonatomic) NSArray<NSValue *> *images;   // mach headers dyld added for this app, executable first
@end

extern NSNotificationName const GuestRuntimeWindowsChangedNotification;

@implementation GuestAppRecord
// The desktop window follows rotation requests right away (GuestContainerView listens).
- (void)setRequestedOrientation:(NSInteger)requestedOrientation {
    _requestedOrientation = requestedOrientation;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:GuestRuntimeWindowsChangedNotification object:nil];
    });
}
@end

static NSMutableArray<GuestAppRecord *> *gApps;
static GuestAppRecord *gLaunching;                  // the app whose launch is in progress
static GuestAppRecord *gActive;                     // the app the user works with
static id gHostAppDelegate;

static const void *kRecordKey = &kRecordKey;
static const void *kLevelKey = &kLevelKey;
static const void *kHostKey = &kHostKey;

/// Guest windows sit this far below their requested level: under iDesk's own window (solid black), so nothing
/// of them shows on the iPhone screen; the user sees them projected in the desktop window.
static const UIWindowLevel kHiddenLevelOffset = -100000;

static NSError *GuestError(NSString *message) {
    return [NSError errorWithDomain:@"iDesk.Guest" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static GuestAppRecord *RecordOfWindow(UIWindow *window) {
    return window ? objc_getAssociatedObject(window, kRecordKey) : nil;
}

static GuestAppRecord *RecordWithHandle(UIWindow *handle) {
    for (GuestAppRecord *app in gApps) if (app.handle == handle) return app;
    return RecordOfWindow(handle);
}

// MARK: - Finding the image just loaded

static const struct mach_header_64 *FindImage(NSString *executablePath, const char **outName) {
    NSString *wanted = executablePath.stringByResolvingSymlinksInPath;
    for (uint32_t i = _dyld_image_count(); i-- > 0;) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *path = [NSString stringWithUTF8String:name].stringByResolvingSymlinksInPath;
        if ([path isEqualToString:wanted]) {
            if (outName) *outName = name;
            return (const struct mach_header_64 *)_dyld_get_image_header(i);
        }
    }
    return NULL;
}

typedef int (*GuestMain)(int, char **, char **, char **);

static GuestMain FindEntryPoint(const struct mach_header_64 *header) {
    const struct load_command *cmd = (const struct load_command *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (cmd->cmd == LC_MAIN) {
            const struct entry_point_command *entry = (const struct entry_point_command *)cmd;
            return (GuestMain)((uintptr_t)header + entry->entryoff);
        }
        cmd = (const struct load_command *)((uintptr_t)cmd + cmd->cmdsize);
    }
    return NULL;
}

static BOOL ClassConforms(Class cls, Protocol *protocol) {
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        if (class_conformsToProtocol(c, protocol)) return YES;
    }
    return NO;
}

/// Calls `body` with every class defined in the app's own images, executable first, until it returns YES.
/// Read from each image's class list, not by name: two apps often both have an Objective-C class called
/// "AppDelegate" or "SceneDelegate", and the runtime's name lookup only knows one of them.
static void ForEachClassOfApp(GuestAppRecord *record, BOOL (^body)(Class cls)) {
    const char *segments[] = { "__DATA_CONST", "__DATA", "__DATA_DIRTY" };
    for (NSValue *value in record.images) {
        const struct mach_header_64 *header = value.pointerValue;
        for (size_t s = 0; s < 3; s++) {
            unsigned long size = 0;
            void *const *list = (void *const *)getsectiondata(header, segments[s], "__objc_classlist", &size);
            for (unsigned long i = 0; list && i < size / sizeof(void *); i++) {
                if (list[i] && body((__bridge Class)list[i])) return;
            }
        }
    }
}

/// The app's own class with this name (Objective-C or "Module.Class"); the runtime's answer if it has none.
static Class AppClassNamed(GuestAppRecord *record, NSString *name) {
    if (!name.length) return Nil;
    __block Class found = Nil;
    ForEachClassOfApp(record, ^BOOL(Class cls) {
        if ([NSStringFromClass(cls) isEqualToString:name]) found = cls;
        return found != Nil;
    });
    return found ?: NSClassFromString(name);
}

/// Fallback when main() did not name the app delegate: a class of the app that adopts UIApplicationDelegate.
static Class FindAppDelegateClass(GuestAppRecord *record) {
    __block Class best = Nil;
    ForEachClassOfApp(record, ^BOOL(Class cls) {
        if (!ClassConforms(cls, @protocol(UIApplicationDelegate))) return NO;
        if (!best) best = cls;
        if ([NSStringFromClass(cls) hasSuffix:@"AppDelegate"]) { best = cls; return YES; }
        return NO;
    });
    return best;
}

// MARK: - Dynamic subclasses

/// The dynamic subclass of `original` used for guest objects ("iDeskGuest_<name>"), created by `setup` the first
/// time. Two apps can each have a class with the same name (AppDelegate…), so a subclass is only reused when its
/// superclass is that exact class; otherwise the name gets a numeric suffix.
static Class GuestSubclass(Class original, void (^setup)(Class sub)) {
    for (int n = 0; n < 64; n++) {
        NSString *name = n == 0 ? [NSString stringWithFormat:@"iDeskGuest_%s", class_getName(original)]
                                : [NSString stringWithFormat:@"iDeskGuest%d_%s", n, class_getName(original)];
        Class existing = objc_lookUpClass(name.UTF8String);
        if (existing) {
            if (class_getSuperclass(existing) == original) return existing;
            continue;
        }
        Class sub = objc_allocateClassPair(original, name.UTF8String, 0);
        if (!sub) continue;
        setup(sub);
        objc_registerClassPair(sub);
        return sub;
    }
    return Nil;
}

// MARK: - Replacing the app delegate

static UISceneConfiguration *HostSceneConfiguration(id self, SEL _cmd, UIApplication *app,
                                                    UISceneSession *session, UISceneConnectionOptions *options) {
    // New scenes (display plugged in again…) must still belong to iDesk, not to the guest app.
    return [gHostAppDelegate application:app configurationForConnectingSceneSession:session options:options];
}

/// Makes the guest's delegate UIApplication.delegate so `UIApplication.shared.delegate as! AppDelegate`
/// in the guest does not crash (with several apps, GuestShims answers each app with its own delegate).
/// A dynamic subclass keeps scene selection with iDesk.
static void AdoptAppDelegate(GuestAppRecord *record, id delegate) {
    UIApplication *app = UIApplication.sharedApplication;
    if (!gHostAppDelegate) gHostAppDelegate = app.delegate;
    record.appDelegate = delegate;
    GuestShimsSetAppDelegate(record.shimID, delegate);

    Class sub = GuestSubclass(object_getClass(delegate), ^(Class cls) {
        class_addMethod(cls, @selector(application:configurationForConnectingSceneSession:options:),
                        (IMP)HostSceneConfiguration, "@@:@@@");
    });
    if (sub) object_setClass(delegate, sub);
    app.delegate = delegate;
}

// MARK: - Guest windows

BOOL GuestSyntheticHitTest = NO;

/// The class iDesk put between the window and its own class (ShieldFromRealTouches). The window's class may be a
/// subclass of it by now (KVO, or the app subclassing at runtime): "super" must be counted from iDesk's class, not
/// from the window's current one, or the call comes back here forever (TikTok overflowed the stack).
static Class ShieldClass(id window) {
    for (Class c = object_getClass(window); c; c = class_getSuperclass(c)) {
        if (!strncmp(class_getName(c), "iDeskGuest", 10)) return c;
    }
    return Nil;
}

static UIView *GuestWindowHitTest(UIWindow *self, SEL _cmd, CGPoint point, UIEvent *event) {
    if (!GuestSyntheticHitTest) return nil;
    Class shield = ShieldClass(self);
    if (!shield) return nil;
    struct objc_super parent = { self, class_getSuperclass(shield) };
    return ((UIView *(*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&parent, _cmd, point, event);
}

static BOOL GuestWindowCannotBecomeKey(id self, SEL _cmd) { return NO; }

/// A guest window still belongs to the iPhone scene, so UIKit would also deliver real fingers on the
/// trackpad to it. hitTest returns nil for every lookup not made by GuestTouch,
/// so the guest only receives the synthetic touches from the desktop pointer.
static void ShieldFromRealTouches(UIWindow *window) {
    Class original = object_getClass(window);
    if (ShieldClass(window)) return;          // already shielded (perhaps under a KVO subclass)
    Class sub = GuestSubclass(original, ^(Class cls) {
        Method m = class_getInstanceMethod(UIView.class, @selector(hitTest:withEvent:));
        class_addMethod(cls, @selector(hitTest:withEvent:), (IMP)GuestWindowHitTest, method_getTypeEncoding(m));
        // Do not let a guest window become key (happens when tapping a text field): the keyboard must
        // stay with iDesk; typed text is forwarded to the guest's focused field through GuestTouch.
        class_addMethod(cls, @selector(canBecomeKeyWindow), (IMP)GuestWindowCannotBecomeKey, "B@:");
        class_addMethod(cls, NSSelectorFromString(@"_canBecomeKeyWindow"), (IMP)GuestWindowCannotBecomeKey, "B@:");
    });
    if (sub) object_setClass(window, sub);
}

static void (*gSetWindowLevel)(id, SEL, UIWindowLevel);
static UIWindowLevel (*gGetWindowLevel)(id, SEL);

/// The level the guest asked for (it keeps seeing that one; UIKit sees it lowered by kHiddenLevelOffset).
static UIWindowLevel RequestedLevel(UIWindow *window) {
    NSNumber *level = objc_getAssociatedObject(window, kLevelKey);
    return level ? level.doubleValue : gGetWindowLevel(window, @selector(windowLevel));
}

static void ShimSetWindowLevel(UIWindow *self, SEL _cmd, UIWindowLevel level) {
    if (!RecordOfWindow(self)) return gSetWindowLevel(self, _cmd, level);
    objc_setAssociatedObject(self, kLevelKey, @(level), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gSetWindowLevel(self, _cmd, level + kHiddenLevelOffset);
}

/// Guest code comparing or deriving levels ("one above the key window") must see what it set.
/// Only a direct call from guest code: UIKit ordering windows, even on the guest's behalf, sees the real level.
static UIWindowLevel ShimGetWindowLevel(UIWindow *self, SEL _cmd) {
    if (GuestShimsIsGuestCode(__builtin_return_address(0)) && RecordOfWindow(self)) return RequestedLevel(self);
    return gGetWindowLevel(self, _cmd);
}

/// Windows UIKit creates for itself (keyboard, text effects…) are not the app's, even when the app's code
/// happens to be on the stack.
static BOOL IsSystemWindow(UIWindow *window) {
    const char *name = class_getName(object_getClass(window));
    static const char *prefixes[] = { "_UI", "UIText", "UIRemote", "UIInput", "UIEditing", "UIKeyboard" };
    for (size_t i = 0; i < sizeof(prefixes) / sizeof(prefixes[0]); i++) {
        if (!strncmp(name, prefixes[i], strlen(prefixes[i]))) return YES;
    }
    return NO;
}

static void AdoptWindow(GuestAppRecord *record, UIWindow *window) {
    if (!record || !window || RecordOfWindow(window) || IsSystemWindow(window)) return;
    objc_setAssociatedObject(window, kRecordKey, record, OBJC_ASSOCIATION_ASSIGN);
    [record.windows addObject:window];
    ShieldFromRealTouches(window);
    ShimSetWindowLevel(window, @selector(setWindowLevel:), gGetWindowLevel(window, @selector(windowLevel)));
}

/// A window created by a guest app's code (anywhere on the stack), or during its launch.
static void AttributeNewWindow(UIWindow *window) {
    if (!window || !gApps.count) return;
    int app = GuestShimsCallerApp(NO);
    GuestAppRecord *record = gLaunching;
    for (GuestAppRecord *r in gApps) if (r.shimID == app) record = r;
    AdoptWindow(record, window);
}

static id (*gInitWithFrame)(id, SEL, CGRect);
static id (*gInitWithScene)(id, SEL, UIWindowScene *);
static void (*gSetHidden)(id, SEL, BOOL);
static void (*gMakeKeyAndVisible)(id, SEL);

static id ShimInitWithFrame(id self, SEL _cmd, CGRect frame) {
    UIWindow *window = gInitWithFrame(self, _cmd, frame);
    AttributeNewWindow(window);
    return window;
}

static id ShimInitWithScene(id self, SEL _cmd, UIWindowScene *scene) {
    UIWindow *window = gInitWithScene(self, _cmd, scene);
    AttributeNewWindow(window);
    return window;
}

/// A window shown on the iPhone scene that nobody claimed: not iDesk's (those were there before any guest, or
/// belong to another scene), not UIKit's own. It can only be a guest's whose creation could not be attributed
/// (created by a system framework on its behalf): give it to the app the user works with, so it does not end up
/// on the iPhone screen.
static void AdoptStray(UIWindow *window) {
    if (!gApps.count || RecordOfWindow(window) || objc_getAssociatedObject(window, kHostKey) || IsSystemWindow(window)) return;
    GuestAppRecord *record = gLaunching ?: gActive;
    UIWindowScene *scene = window.windowScene;
    if (!record || (scene && scene != record.scene)) return;
    AdoptWindow(record, window);
}

/// A scene-less window of an old-style app would join the app's only scene by itself: give it the iPhone scene.
static void JoinScene(UIWindow *window) {
    GuestAppRecord *record = RecordOfWindow(window);
    if (record && !window.windowScene && record.scene) window.windowScene = record.scene;
}

static void ShimSetHidden(UIWindow *self, SEL _cmd, BOOL hidden) {
    if (!hidden) {
        AdoptStray(self);
        JoinScene(self);
    }
    gSetHidden(self, _cmd, hidden);
}

/// The window an app makes key is its main window (it may switch: a splash window first, the real one later).
static void ShimMakeKeyAndVisible(UIWindow *self, SEL _cmd) {
    AdoptStray(self);
    JoinScene(self);
    gMakeKeyAndVisible(self, _cmd);
    GuestAppRecord *record = RecordOfWindow(self);
    if (record) {
        record.window = self;
        GuestShimsSetWindow(record.shimID, self);
    }
}

static void TrackWindowsOnce(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = UIWindow.class;
        gInitWithFrame = (void *)GuestShimsReplaceMethod(cls, @selector(initWithFrame:), NO, (IMP)ShimInitWithFrame);
        gInitWithScene = (void *)GuestShimsReplaceMethod(cls, @selector(initWithWindowScene:), NO, (IMP)ShimInitWithScene);
        gSetWindowLevel = (void *)GuestShimsReplaceMethod(cls, @selector(setWindowLevel:), NO, (IMP)ShimSetWindowLevel);
        gGetWindowLevel = (void *)GuestShimsReplaceMethod(cls, @selector(windowLevel), NO, (IMP)ShimGetWindowLevel);
        gSetHidden = (void *)GuestShimsReplaceMethod(cls, @selector(setHidden:), NO, (IMP)ShimSetHidden);
        gMakeKeyAndVisible = (void *)GuestShimsReplaceMethod(cls, @selector(makeKeyAndVisible), NO, (IMP)ShimMakeKeyAndVisible);
        // Everything on screen before the first guest is iDesk's.
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                objc_setAssociatedObject(window, kHostKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    });
}

// MARK: - System screens

NSNotificationName const GuestRuntimeOpenURLNotification = @"iDeskGuestOpenURL";
NSNotificationName const GuestRuntimeWindowsChangedNotification = @"iDeskGuestWindowsChanged";

/// Screens iOS draws in another process and only shows inside the app's window (App Store, mail, share sheet,
/// pickers, sign-in). They cannot be projected onto the desktop and ignore synthetic touches, so inside a guest
/// window they would cover the app invisibly and freeze it.
static BOOL IsSystemScreen(UIViewController *controller) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"SKStoreProductViewController", @"SKCloudServiceSetupViewController", @"MFMailComposeViewController",
                  @"MFMessageComposeViewController", @"UIActivityViewController", @"UIDocumentPickerViewController",
                  @"UIDocumentBrowserViewController", @"PHPickerViewController", @"UIImagePickerController",
                  @"CNContactPickerViewController", @"EKEventEditViewController", @"PKAddPassesViewController",
                  @"PKPaymentAuthorizationViewController", @"ASAuthorizationController", @"QLPreviewController"];
    });
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (cls && [controller isKindOfClass:cls]) return YES;
    }
    return NO;
}

/// The topmost controller of iDesk's own window on the iPhone.
static UIViewController *HostPresenter(UIWindowScene *scene) {
    for (UIWindow *window in scene.windows) {
        if (!objc_getAssociatedObject(window, kHostKey) || window.isHidden || !window.rootViewController) continue;
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
        return top;
    }
    return nil;
}

static const void *kSafariURLKey = &kSafariURLKey;
static void (*gPresent)(id, SEL, UIViewController *, BOOL, id);
static id (*gSafariInit)(id, SEL, NSURL *);
static id (*gSafariInitConfigured)(id, SEL, NSURL *, id);

static id ShimSafariInit(id self, SEL _cmd, NSURL *url) {
    self = gSafariInit(self, _cmd, url);
    if (self && url) objc_setAssociatedObject(self, kSafariURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}

static id ShimSafariInitConfigured(id self, SEL _cmd, NSURL *url, id configuration) {
    self = gSafariInitConfigured(self, _cmd, url, configuration);
    if (self && url) objc_setAssociatedObject(self, kSafariURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}

/// A guest presenting a system screen: show it on the iPhone screen, where it can be used with real touches.
/// An in-app browser (SFSafariViewController) opens as a web window on the desktop instead.
static void ShimPresent(UIViewController *self, SEL _cmd, UIViewController *controller, BOOL animated, void (^completion)(void)) {
    GuestAppRecord *record = RecordOfWindow(self.viewIfLoaded.window);
    if (record && controller) {
        NSURL *url = objc_getAssociatedObject(controller, kSafariURLKey);
        if (url) {
            [NSNotificationCenter.defaultCenter postNotificationName:GuestRuntimeOpenURLNotification object:url];
            if (completion) completion();
            return;
        }
        UIViewController *host = IsSystemScreen(controller) ? HostPresenter(record.scene) : nil;
        if (host) return gPresent(host, _cmd, controller, animated, completion);
    }
    gPresent(self, _cmd, controller, animated, completion);
}

/// SafariServices is loaded with the first app that uses it.
static void HookSystemScreens(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gPresent = (void *)GuestShimsReplaceMethod(UIViewController.class, @selector(presentViewController:animated:completion:), NO, (IMP)ShimPresent);
    });
    static BOOL safari;
    Class cls = NSClassFromString(@"SFSafariViewController");
    if (cls && !safari) {
        safari = YES;
        gSafariInit = (void *)GuestShimsReplaceMethod(cls, NSSelectorFromString(@"initWithURL:"), NO, (IMP)ShimSafariInit);
        gSafariInitConfigured = (void *)GuestShimsReplaceMethod(cls, NSSelectorFromString(@"initWithURL:configuration:"), NO, (IMP)ShimSafariInitConfigured);
    }
}

// MARK: - Rotation

/// What an orientation mask asks for: 2 landscape only, 1 portrait only, 0 either / nothing.
static NSInteger Orientation(UIInterfaceOrientationMask mask) {
    BOOL portrait = (mask & UIInterfaceOrientationMaskPortrait) || (mask & UIInterfaceOrientationMaskPortraitUpsideDown);
    BOOL landscape = (mask & UIInterfaceOrientationMaskLandscape) != 0;
    return landscape && !portrait ? 2 : (portrait && !landscape ? 1 : 0);
}

static GuestAppRecord *CallingRecord(void) {
    int app = GuestShimsCallerApp(NO);
    for (GuestAppRecord *r in gApps) if (r.shimID == app) return r;
    return nil;
}

// MARK: - Notifications

NSNotificationName const GuestRuntimeNotificationNotification = @"iDeskGuestNotification";

/// Local notifications a guest schedules, by "<app>:<identifier>": the block that will show it, so it can be cancelled.
static NSMutableDictionary<NSString *, dispatch_block_t> *gPendingNotifications;
static void (*gAddRequest)(id, SEL, UNNotificationRequest *, id);
static void (*gRequestAuthorization)(id, SEL, UNAuthorizationOptions, id);
static void (*gRemovePending)(id, SEL, NSArray<NSString *> *);
static void (*gRemoveAllPending)(id, SEL);

static NSString *PendingKey(GuestAppRecord *record, NSString *identifier) {
    return [NSString stringWithFormat:@"%d:%@", record.shimID, identifier ?: @""];
}

/// A guest's notification goes to the desktop instead of iOS: iOS would show it as iDesk's (if iDesk may notify at
/// all), and it would never reach the app's window. Shown while iDesk runs, at the time it was scheduled for.
static void ShimAddRequest(id self, SEL _cmd, UNNotificationRequest *request, void (^completion)(NSError *)) {
    GuestAppRecord *record = CallingRecord();
    if (!record || !request) return gAddRequest(self, _cmd, request, completion);
    UNNotificationContent *content = request.content;
    NSDictionary *info = @{@"bundlePath": record.bundlePath ?: @"",
                           @"title": content.title ?: @"", @"subtitle": content.subtitle ?: @"", @"body": content.body ?: @""};
    NSTimeInterval delay = 0;
    UNNotificationTrigger *trigger = request.trigger;
    if ([trigger respondsToSelector:@selector(nextTriggerDate)]) {
        NSDate *next = [(id)trigger nextTriggerDate];
        if (!next) { if (completion) completion(nil); return; }
        delay = MAX(0, next.timeIntervalSinceNow);
    }
    NSString *key = PendingKey(record, request.identifier);
    if (delay <= 7 * 24 * 3600 && (content.title.length || content.body.length)) {
        dispatch_block_t show = dispatch_block_create(0, ^{
            [gPendingNotifications removeObjectForKey:key];
            [NSNotificationCenter.defaultCenter postNotificationName:GuestRuntimeNotificationNotification object:nil userInfo:info];
        });
        dispatch_block_t old = gPendingNotifications[key];
        if (old) dispatch_block_cancel(old);
        gPendingNotifications[key] = show;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), show);
    }
    if (completion) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ completion(nil); });
}

/// Guests may always notify: their notifications only appear on the desktop.
static void ShimRequestAuthorization(id self, SEL _cmd, UNAuthorizationOptions options, void (^completion)(BOOL, NSError *)) {
    if (!CallingRecord()) return gRequestAuthorization(self, _cmd, options, completion);
    if (completion) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ completion(YES, nil); });
}

static void ShimRemovePending(id self, SEL _cmd, NSArray<NSString *> *identifiers) {
    GuestAppRecord *record = CallingRecord();
    if (!record) return gRemovePending(self, _cmd, identifiers);
    for (NSString *identifier in identifiers) {
        NSString *key = PendingKey(record, identifier);
        dispatch_block_t block = gPendingNotifications[key];
        if (block) dispatch_block_cancel(block);
        [gPendingNotifications removeObjectForKey:key];
    }
}

static void ShimRemoveAllPending(id self, SEL _cmd) {
    GuestAppRecord *record = CallingRecord();
    if (!record) return gRemoveAllPending(self, _cmd);
    NSString *prefix = [NSString stringWithFormat:@"%d:", record.shimID];
    for (NSString *key in gPendingNotifications.allKeys) {
        if (![key hasPrefix:prefix]) continue;
        dispatch_block_cancel(gPendingNotifications[key]);
        [gPendingNotifications removeObjectForKey:key];
    }
}

static void HookNotifications(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gPendingNotifications = [NSMutableDictionary dictionary];
        Class cls = UNUserNotificationCenter.class;
        gAddRequest = (void *)GuestShimsReplaceMethod(cls, @selector(addNotificationRequest:withCompletionHandler:), NO, (IMP)ShimAddRequest);
        gRequestAuthorization = (void *)GuestShimsReplaceMethod(cls, @selector(requestAuthorizationWithOptions:completionHandler:), NO, (IMP)ShimRequestAuthorization);
        gRemovePending = (void *)GuestShimsReplaceMethod(cls, @selector(removePendingNotificationRequestsWithIdentifiers:), NO, (IMP)ShimRemovePending);
        gRemoveAllPending = (void *)GuestShimsReplaceMethod(cls, @selector(removeAllPendingNotificationRequests), NO, (IMP)ShimRemoveAllPending);
    });
}

static void (*gRequestGeometry)(id, SEL, id, id);
static void (*gSetOrientation)(id, SEL, UIInterfaceOrientation);
static void (*gSetOrientationAnimated)(id, SEL, UIInterfaceOrientation, BOOL);

/// An app turning the phone (video players going fullscreen do): the scene is iDesk's and must not rotate.
/// The wish is recorded, and iDesk makes the app's desktop window fill the display instead.
static void ShimRequestGeometry(UIWindowScene *self, SEL _cmd, id preferences, id errorHandler) {
    GuestAppRecord *record = CallingRecord();
    if (!record) return gRequestGeometry(self, _cmd, preferences, errorHandler);
    if ([preferences respondsToSelector:@selector(interfaceOrientations)]) {
        record.requestedOrientation = Orientation(((UIInterfaceOrientationMask (*)(id, SEL))objc_msgSend)(
            preferences, @selector(interfaceOrientations)));
    }
}

static NSInteger OrientationOf(UIInterfaceOrientation orientation) {
    return UIInterfaceOrientationIsLandscape(orientation) ? 2 : (UIInterfaceOrientationIsPortrait(orientation) ? 1 : 0);
}

/// The older way: `UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")`.
static void ShimSetOrientation(UIDevice *self, SEL _cmd, UIInterfaceOrientation orientation) {
    GuestAppRecord *record = CallingRecord();
    if (!record) return gSetOrientation(self, _cmd, orientation);
    record.requestedOrientation = OrientationOf(orientation);
}

static void ShimSetOrientationAnimated(UIDevice *self, SEL _cmd, UIInterfaceOrientation orientation, BOOL animated) {
    GuestAppRecord *record = CallingRecord();
    if (!record) return gSetOrientationAnimated(self, _cmd, orientation, animated);
    record.requestedOrientation = OrientationOf(orientation);
}

static void HookRotationOnce(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gRequestGeometry = (void *)GuestShimsReplaceMethod(UIWindowScene.class, NSSelectorFromString(@"requestGeometryUpdateWithPreferences:errorHandler:"), NO, (IMP)ShimRequestGeometry);
        gSetOrientation = (void *)GuestShimsReplaceMethod(UIDevice.class, NSSelectorFromString(@"setOrientation:"), NO, (IMP)ShimSetOrientation);
        gSetOrientationAnimated = (void *)GuestShimsReplaceMethod(UIDevice.class, NSSelectorFromString(@"setOrientation:animated:"), NO, (IMP)ShimSetOrientationAnimated);
    });
}

// MARK: - Driving the lifecycle

static NSSet<UIWindow *> *AllWindows(void) {
    NSMutableSet *set = [NSMutableSet set];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            [set addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    return set;
}

static UISceneConnectionOptions *EmptyConnectionOptions(void) {
    // This class has no public init; create an empty instance through the runtime.
    return ((id (*)(id, SEL))objc_msgSend)([UISceneConnectionOptions alloc], sel_registerName("init"));
}

static UIWindow *WindowOf(id object) {
    if (![object respondsToSelector:@selector(window)]) return nil;
    id window = [object window];
    return [window isKindOfClass:UIWindow.class] ? window : nil;
}

/// Creates the guest's scene delegate and "connects" it to iDesk's scene.
static UIWindow *ConnectScene(GuestAppRecord *record, Class sceneDelegateClass, NSString *storyboardName,
                              UIWindowScene *scene) {
    id sceneDelegate = [[sceneDelegateClass alloc] init];
    record.sceneDelegate = sceneDelegate;

    UIWindow *storyboardWindow = nil;
    if (storyboardName.length && [sceneDelegate respondsToSelector:@selector(setWindow:)]) {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:storyboardName bundle:record.bundle];
        storyboardWindow = [[UIWindow alloc] initWithWindowScene:scene];
        storyboardWindow.rootViewController = [storyboard instantiateInitialViewController];
        [sceneDelegate setWindow:storyboardWindow];
    }
    if ([sceneDelegate respondsToSelector:@selector(scene:willConnectToSession:options:)]) {
        [sceneDelegate scene:scene willConnectToSession:scene.session options:EmptyConnectionOptions()];
    }
    return WindowOf(sceneDelegate) ?: storyboardWindow;
}

static UIWindow *LaunchWithDelegate(GuestAppRecord *record, id<UIApplicationDelegate> delegate, UIWindowScene *scene) {
    UIApplication *app = UIApplication.sharedApplication;
    NSDictionary *info = record.bundle.infoDictionary;
    NSSet<UIWindow *> *before = AllWindows();

    // The guest's original scene-selection method (not the one masked by the dynamic subclass).
    SEL configSel = @selector(application:configurationForConnectingSceneSession:options:);
    Method configMethod = class_getInstanceMethod(class_getSuperclass(object_getClass(delegate)), configSel);
    NSDictionary *plistScene = [info[@"UIApplicationSceneManifest"][@"UISceneConfigurations"]
                                [@"UIWindowSceneSessionRoleApplication"] firstObject];
    BOOL sceneBased = configMethod != NULL || plistScene != nil;

    // Old-style app (no scenes): UIKit builds the window from the main storyboard before calling the delegate.
    UIWindow *mainStoryboardWindow = nil;
    NSString *mainStoryboard = info[@"UIMainStoryboardFile"];
    if (!sceneBased && mainStoryboard.length) {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:mainStoryboard bundle:record.bundle];
        mainStoryboardWindow = [[UIWindow alloc] initWithWindowScene:scene];
        mainStoryboardWindow.rootViewController = [storyboard instantiateInitialViewController];
        if ([delegate respondsToSelector:@selector(setWindow:)]) [delegate setWindow:mainStoryboardWindow];
    }

    if ([delegate respondsToSelector:@selector(application:willFinishLaunchingWithOptions:)]) {
        [delegate application:app willFinishLaunchingWithOptions:nil];
    }
    if ([delegate respondsToSelector:@selector(application:didFinishLaunchingWithOptions:)]) {
        [delegate application:app didFinishLaunchingWithOptions:nil];
    } else if ([delegate respondsToSelector:@selector(applicationDidFinishLaunching:)]) {
        [delegate applicationDidFinishLaunching:app];
    }

    // Scene configuration: ask the delegate first (like UIKit), otherwise read Info.plist.
    Class sceneDelegateClass = Nil;
    NSString *sceneStoryboard = nil;
    if (configMethod) {
        UISceneConfiguration *(*imp)(id, SEL, id, id, id) = (void *)method_getImplementation(configMethod);
        UISceneConfiguration *config = imp(delegate, configSel, app, scene.session, EmptyConnectionOptions());
        sceneDelegateClass = config.delegateClass;
        sceneStoryboard = [config.storyboard valueForKey:@"name"];
    }
    if (!sceneDelegateClass && plistScene[@"UISceneDelegateClassName"]) {
        sceneDelegateClass = AppClassNamed(record, plistScene[@"UISceneDelegateClassName"]);
        sceneStoryboard = plistScene[@"UISceneStoryboardFile"];
    }

    UIWindow *window = nil;
    if (sceneDelegateClass) window = ConnectScene(record, sceneDelegateClass, sceneStoryboard, scene);
    if (!window) window = WindowOf(delegate) ?: mainStoryboardWindow;
    if (!window) {
        // The delegate does not expose its window: take a new window of this app that appeared during launch.
        NSMutableSet *created = [AllWindows() mutableCopy];
        [created minusSet:before];
        for (UIWindow *w in created) {
            if (w.rootViewController && RecordOfWindow(w) == record) { window = w; break; }
        }
    }
    if (window && !window.windowScene) window.windowScene = scene;

    // A real launch continues with "entering the foreground" and "became active"; many apps start their work there.
    BOOL active = scene.activationState == UISceneActivationStateForegroundActive;
    id sceneDelegate = record.sceneDelegate;
    if (sceneDelegate) {
        if ([sceneDelegate respondsToSelector:@selector(sceneWillEnterForeground:)]) {
            [sceneDelegate sceneWillEnterForeground:scene];
        }
        if (active && [sceneDelegate respondsToSelector:@selector(sceneDidBecomeActive:)]) {
            [sceneDelegate sceneDidBecomeActive:scene];
        }
    } else if (active && [delegate respondsToSelector:@selector(applicationDidBecomeActive:)]) {
        [delegate applicationDidBecomeActive:app];
    }
    return window;
}

/// A method implemented by `cls` itself (not inherited), so the superclass is never patched by mistake.
static Method OwnInstanceMethod(Class cls, SEL selector) {
    if (!cls) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method found = NULL;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) { found = methods[i]; break; }
    }
    free(methods);
    return found;
}

static id RefuseInit(id self, SEL _cmd) { return nil; }

/// Runs the guest's main() up to UIApplicationMain, like a real launch: whatever the app sets up first
/// (crash reporters, SDK keys, environment) happens. Returns why main() stopped.
static NSString *RunMain(GuestMain entry) {
    // UIApplicationMain creates a UIEventFetcher (the touch event thread) before even creating UIApplication.
    // A second one would grab every event without delivering it, so all of iDesk would lose touch input.
    // While the guest's main() runs, that class's init returns nil.
    Method fetcherInit = OwnInstanceMethod(NSClassFromString(@"UIEventFetcher"), @selector(init));
    IMP originalInit = fetcherInit ? method_setImplementation(fetcherInit, (IMP)RefuseInit) : NULL;
    char **argv = *_NSGetArgv();
    NSString *stop = @"main() returned";
    GuestShimsResetMainCall();
    @try {
        entry(1, argv, *_NSGetEnviron(), NULL);
    } @catch (NSException *exception) {
        stop = exception.reason ?: exception.name;
    } @finally {
        if (fetcherInit) method_setImplementation(fetcherInit, originalInit);
    }
    NSLog(@"[iDesk] guest main() stopped at: %@", stop);
    return stop;
}

/// The app's own UIApplication subclass (UIApplicationMain's 3rd argument), so `UIApplication.shared as! MyApp`
/// and its overrides work. Only when it adds no stored properties: the existing object has no room for them.
static void AdoptPrincipalClass(GuestAppRecord *record, NSString *name) {
    Class cls = AppClassNamed(record, name);
    UIApplication *app = UIApplication.sharedApplication;
    Class current = object_getClass(app);
    if (!cls || cls == current || ![cls isSubclassOfClass:current]) return;
    if (class_getInstanceSize(cls) != class_getInstanceSize(current)) {
        NSLog(@"[iDesk] guest UIApplication subclass %@ has stored properties: not adopted", name);
        return;
    }
    object_setClass(app, cls);
}

/// Finds the app delegate the way UIKit would, then drives the launch.
/// - UIKit app (Objective-C or Swift): main() calls UIApplicationMain with the delegate's class name.
/// - SwiftUI app (`@main struct MyApp: App`): SwiftUI calls UIApplicationMain from inside the system framework,
///   so it is not intercepted and UIKit throws "There can only be one UIApplication instance". SwiftUI's own
///   app graph is built by then; finish the launch through its delegate.
static UIWindow *Launch(GuestAppRecord *record, GuestMain entry, UIWindowScene *scene, NSError **error) {
    NSString *stop = entry ? RunMain(entry) : nil;
    Class delegateClass = Nil;
    if (GuestShimsMainCalled()) {
        AdoptPrincipalClass(record, GuestShimsMainPrincipalClass());
        NSString *name = GuestShimsMainDelegateClass();
        delegateClass = AppClassNamed(record, name);
    }
    BOOL swiftUI = !GuestShimsMainCalled() && [stop containsString:@"UIApplication"];
    if (!delegateClass && !swiftUI) delegateClass = FindAppDelegateClass(record);
    if (!delegateClass) delegateClass = NSClassFromString(@"SwiftUI.AppDelegate");
    if (!delegateClass) {
        if (error) *error = GuestError(NSLocalizedString(@"Could not find the app’s app delegate.", nil));
        return nil;
    }
    id<UIApplicationDelegate> delegate = [[delegateClass alloc] init];
    AdoptAppDelegate(record, delegate);
    return LaunchWithDelegate(record, delegate, scene);
}

// MARK: - API

@implementation GuestRuntime

+ (UIWindow *)launchBundleAtPath:(NSString *)bundlePath scene:(UIWindowScene *)scene error:(NSError **)error {
    if (!gApps) gApps = [NSMutableArray array];
    for (GuestAppRecord *app in gApps) {
        if ([app.bundlePath isEqualToString:bundlePath]) return app.handle;
    }
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *executable = bundle.executablePath;
    if (!executable) {
        if (error) *error = GuestError(NSLocalizedString(@"Cannot read the app bundle.", nil));
        return nil;
    }

    TrackWindowsOnce();
    HookRotationOnce();
    GuestAppRecord *record = [GuestAppRecord new];
    record.bundlePath = bundlePath;
    record.bundle = bundle;
    record.scene = scene;
    record.windows = [NSHashTable weakObjectsHashTable];
    // Created before the app is registered, so it is not mistaken for one of its windows.
    record.handle = [[UIWindow alloc] initWithFrame:CGRectZero];
    objc_setAssociatedObject(record.handle, kHostKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    record.shimID = GuestShimsBeginApp(bundle);

    uint32_t imagesBefore = _dyld_image_count();
    void *handle = dlopen(executable.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        GuestShimsEndLoading();
        NSString *reason = [NSString stringWithUTF8String:dlerror() ?: "unknown"];
        if (error) *error = GuestError([NSString stringWithFormat:NSLocalizedString(@"Could not load the app: %@", nil), reason]);
        return nil;
    }
    // No way back from here: the guest app's code is now in the process.
    [gApps addObject:record];
    GuestShimsDidLoad(record.shimID);
    HookSystemScreens();
    HookNotifications();
    unsigned repaired = GuestRepairCategories(imagesBefore);
    if (repaired) NSLog(@"[iDesk] added accessors for %u @dynamic properties of the guest app", repaired);

    const struct mach_header_64 *header = FindImage(executable, NULL);
    NSMutableArray<NSValue *> *images = [NSMutableArray array];
    if (header) [images addObject:[NSValue valueWithPointer:header]];
    for (uint32_t i = imagesBefore; i < _dyld_image_count(); i++) {
        const struct mach_header *image = _dyld_get_image_header(i);
        if (image && image != (const void *)header && image->magic == MH_MAGIC_64 && !(image->flags & 0x80000000)) {
            [images addObject:[NSValue valueWithPointer:image]];
        }
    }
    record.images = images;

    UIWindow *window = nil;
    NSError *launchError = nil;
    gLaunching = record;
    gActive = record;
    @try {
        window = Launch(record, header ? FindEntryPoint(header) : NULL, scene, &launchError);
    } @catch (NSException *exception) {
        launchError = GuestError([NSString stringWithFormat:NSLocalizedString(@"The app reported an error while launching: %@", nil), exception.reason]);
    } @finally {
        gLaunching = nil;
        GuestShimsEndLoading();
    }
    if (launchError && !window) {
        if (error) *error = launchError;
        return nil;
    }
    // Many apps create their window later (after a network check, in an async block…): the desktop window opens
    // now and shows the app's windows as they appear.
    if (window) {
        AdoptWindow(record, window);
        if (!record.window) {
            record.window = window;
            GuestShimsSetWindow(record.shimID, window);
        }
    }
    return record.handle;
}

+ (NSArray<UIWindow *> *)windowsOfAppWithWindow:(UIWindow *)handle {
    GuestAppRecord *record = RecordWithHandle(handle);
    if (!record) return @[];
    NSMutableArray<UIWindow *> *visible = [NSMutableArray array];
    for (UIWindow *window in record.windows) {
        if (!window.isHidden && window.windowScene && window.alpha > 0.01) [visible addObject:window];
    }
    // No main window yet (it never called makeKeyAndVisible): the lowest visible window with content.
    if (!record.window || record.window.isHidden) {
        for (UIWindow *window in visible) {
            if (window.rootViewController && (!record.window || RequestedLevel(window) < RequestedLevel(record.window))) {
                record.window = window;
            }
        }
        if (record.window) GuestShimsSetWindow(record.shimID, record.window);
    }
    // Bottom to top: by requested level, then in the scene's own order.
    NSArray<UIWindow *> *order = record.scene.windows ?: @[];
    [visible sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        UIWindowLevel la = RequestedLevel(a), lb = RequestedLevel(b);
        if (la != lb) return la < lb ? NSOrderedAscending : NSOrderedDescending;
        NSUInteger ia = [order indexOfObject:a], ib = [order indexOfObject:b];
        return ia == ib ? NSOrderedSame : (ia < ib ? NSOrderedAscending : NSOrderedDescending);
    }];
    return visible;
}

+ (UIWindow *)touchWindowAt:(CGPoint)point appWindow:(UIWindow *)handle {
    GuestAppRecord *record = RecordWithHandle(handle);
    for (UIWindow *window in [self windowsOfAppWithWindow:handle].reverseObjectEnumerator) {
        if (window == record.window || GuestTouchHitTest(window, point)) return window;
    }
    return record.window ?: handle;
}

+ (BOOL)appWantsLandscapeWithWindow:(UIWindow *)handle {
    GuestAppRecord *record = RecordWithHandle(handle);
    UIViewController *top = record.window.rootViewController;
    if (!top) return NO;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    // A screen that only works in landscape (a fullscreen video player) wins; then what the app last asked for.
    NSInteger screen = 0;
    @try { screen = Orientation(top.supportedInterfaceOrientations); } @catch (NSException *exception) {}
    if (screen) return screen == 2;
    return record.requestedOrientation == 2;
}

/// The deepest navigation controller on screen under `controller` that can go back.
static UINavigationController *BackableNavigation(UIViewController *controller) {
    if (!controller) return nil;
    UINavigationController *found = nil;
    if ([controller isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)controller;
        found = BackableNavigation(nav.topViewController) ?: (nav.viewControllers.count > 1 ? nav : nil);
        return found;
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return BackableNavigation(((UITabBarController *)controller).selectedViewController);
    }
    // Containers (split views, custom ones, SwiftUI hosting): the visible children, front-most first.
    for (UIViewController *child in controller.childViewControllers.reverseObjectEnumerator) {
        if (!child.viewIfLoaded.window || child.view.isHidden) continue;
        if ((found = BackableNavigation(child))) return found;
    }
    return nil;
}

+ (BOOL)goBackInAppWithWindow:(UIWindow *)handle {
    GuestAppRecord *record = RecordWithHandle(handle);
    UIViewController *top = record.window.rootViewController;
    if (!top) return NO;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    UINavigationController *nav = BackableNavigation(top);
    if (nav) {
        [nav popViewControllerAnimated:YES];
        return YES;
    }
    // A screen shown over the app (a modal sheet) with nowhere to go back to inside it: close it.
    if (top != record.window.rootViewController && !top.isModalInPresentation) {
        [top dismissViewControllerAnimated:YES completion:nil];
        return YES;
    }
    return NO;
}

+ (void)activateAppWithWindow:(UIWindow *)handle {
    GuestAppRecord *record = RecordWithHandle(handle);
    if (!record) return;
    gActive = record;
    GuestShimsSetActiveApp(record.shimID);
}

/// Sends the lifecycle events iOS sends when an app leaves / returns to the screen, to this app only.
static void SendLifecycle(GuestAppRecord *record, BOOL foreground) {
    UIApplication *app = UIApplication.sharedApplication;
    UIScene *scene = record.scene;
    id sceneDelegate = record.sceneDelegate, delegate = record.appDelegate;
    NSArray<NSString *> *sceneEvents = foreground ? @[@"sceneWillEnterForeground:", @"sceneDidBecomeActive:"]
                                                  : @[@"sceneWillResignActive:", @"sceneDidEnterBackground:"];
    NSArray<NSString *> *appEvents = foreground ? @[@"applicationWillEnterForeground:", @"applicationDidBecomeActive:"]
                                                : @[@"applicationWillResignActive:", @"applicationDidEnterBackground:"];
    for (NSUInteger i = 0; i < 2; i++) {
        SEL sceneEvent = NSSelectorFromString(sceneEvents[i]), appEvent = NSSelectorFromString(appEvents[i]);
        if (sceneDelegate && scene && [sceneDelegate respondsToSelector:sceneEvent]) {
            ((void (*)(id, SEL, id))objc_msgSend)(sceneDelegate, sceneEvent, scene);
        } else if (!sceneDelegate && [delegate respondsToSelector:appEvent]) {
            ((void (*)(id, SEL, id))objc_msgSend)(delegate, appEvent, app);
        }
    }
}

static void VisitControllers(UIViewController *controller, void (^visit)(UIViewController *)) {
    if (!controller) return;
    visit(controller);
    for (UIViewController *child in controller.childViewControllers) VisitControllers(child, visit);
    if (controller.presentedViewController.presentingViewController == controller) {
        VisitControllers(controller.presentedViewController, visit);
    }
}

/// The app's code cannot be unloaded, but its memory can shrink: a low-memory warning makes apps (and image
/// libraries such as SDWebImage or Kingfisher, which listen for it) drop their caches.
static void ReleaseMemory(GuestAppRecord *record) {
    UIApplication *app = UIApplication.sharedApplication;
    if ([record.appDelegate respondsToSelector:@selector(applicationDidReceiveMemoryWarning:)]) {
        [record.appDelegate applicationDidReceiveMemoryWarning:app];
    }
    for (UIWindow *window in record.windows) {
        VisitControllers(window.rootViewController, ^(UIViewController *controller) { [controller didReceiveMemoryWarning]; });
    }
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:app
                                                    userInfo:@{@"iDeskReleaseMemory": @YES}];
    [NSURLCache.sharedURLCache removeAllCachedResponses];
}

+ (void)suspendAppWithWindow:(UIWindow *)handle {
    GuestAppRecord *record = RecordWithHandle(handle);
    if (!record || record.suspended) return;
    record.suspended = YES;
    @try { SendLifecycle(record, NO); } @catch (NSException *exception) {
        NSLog(@"[iDesk] guest app threw while going to the background: %@", exception.reason);
    }
    // Once it has settled in the background (and unless it was reopened meanwhile), let it free what it can.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!record.suspended) return;
        @try { ReleaseMemory(record); } @catch (NSException *exception) {
            NSLog(@"[iDesk] guest app threw on a memory warning: %@", exception.reason);
        }
    });
}

+ (void)resumeAppWithWindow:(UIWindow *)handle {
    GuestAppRecord *record = RecordWithHandle(handle);
    if (!record || !record.suspended) return;
    record.suspended = NO;
    @try { SendLifecycle(record, YES); } @catch (NSException *exception) {
        NSLog(@"[iDesk] guest app threw while coming back: %@", exception.reason);
    }
}

+ (void)forwardSceneEvent:(SEL)selector scene:(UIScene *)scene {
    for (GuestAppRecord *app in gApps) {
        if (app.suspended || ![app.sceneDelegate respondsToSelector:selector]) continue;
        ((void (*)(id, SEL, id))objc_msgSend)(app.sceneDelegate, selector, scene);
    }
}

@end
