#import "GuestShims.h"
#import "CrashReporter.h"
#import "MachOImage.h"
#import <Security/Security.h>
#import <CoreText/CoreText.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <stdatomic.h>
#import <pthread.h>
#import <sys/mman.h>
#import <dlfcn.h>

// A guest app is loaded into iDesk's process. Every app then meets the same differences from a normal launch,
// whatever the app is. This file handles them all in one place, never per app:
//
// 1. Entitlements are iDesk's, not the guest's.
//    - Keychain: an explicit access group (shared between a vendor's apps) is refused (errSecMissingEntitlement).
//      It is removed from the guest's SecItem* calls, so items live in iDesk's default group.
//    - App Groups: a missing group container is replaced by a folder in iDesk's Library.
//    - CloudKit crashes without the iCloud entitlement: the guest gets an inert container instead.
//    - HealthKit throws without its entitlement: the authorization request is answered "denied" instead.
// 2. The app has already launched.
//    - main() → UIApplicationMain: recorded (which delegate / UIApplication class the app wants) and stopped,
//      instead of UIKit refusing a second UIApplication. iDesk then drives the lifecycle with that delegate.
//    - BGTaskScheduler only accepts registrations before launch finishes, and throws afterwards: ignored.
//    - Fonts listed in UIAppFonts were never registered (UIKit reads iDesk's Info.plist): registered here.
// 3. The process belongs to iDesk, and possibly to several guest apps at once.
//    - NSBundle.mainBundle and CFBundleGetMainBundle return the bundle of the app whose code asks.
//    - So do UIApplication.delegate, the key window and `windows` (the asking app's window comes first).
//    - iDesk's own texts are still found when a guest bundle stands in as the main bundle.
//    - exit() called by the guest (often an anti-tamper check) is recorded, so the report says why iDesk quit.
// 4. Old libraries in tweaked apps import libstdc++ functions iOS has removed: they do nothing instead of crashing.
//
// "The app whose code asks" is found from the call stack: the nearest frame in a guest app's executable, or
// failing that in one of its frameworks. A system framework working for a guest from a run loop callback has
// no guest frame; it gets the app being loaded, or else the app the user last worked with.
//
// C functions are redirected by rewriting the guest images' symbol pointers (the technique of fishhook) as each
// image is added, before its initializers run. iDesk's own calls and the system libraries are not touched.

NSString *const GuestShimsMainReached = @"iDeskGuestMainReached";

// MARK: - Apps and their images

@interface GuestShimsApp : NSObject
@property (nonatomic) NSBundle *bundle;
@property (nonatomic) CFBundleRef cfBundle;
@property (nonatomic) const char *executableSuffix;    // "/<bundle folder>/<executable>", to recognise its image
/// Bundled into iDesk: the libraries it put into iDesk.app/Frameworks (iDeskFrameworks.txt). nil otherwise.
@property (nonatomic) NSSet<NSString *> *ownLibraries;
@property (nonatomic, weak) id delegate;
@property (nonatomic, weak) UIWindow *window;
@end

@implementation GuestShimsApp
- (void)dealloc {
    if (_cfBundle) CFRelease(_cfBundle);
    free((void *)_executableSuffix);
}
@end

static NSMutableArray<GuestShimsApp *> *gApps;     // index = app id; only ever appended to
static _Atomic int gAppCount;
static int gLoadingApp = -1;
static int gActiveApp = -1;
static NSBundle *gHostBundle;                      // iDesk's real main bundle

typedef struct {
    uintptr_t start, end;      // __TEXT
    int app;
    BOOL executable;           // the app's own executable (not one of its frameworks)
} GuestImage;

static GuestImage gImages[2048];
static _Atomic uint32_t gImageCount;

static GuestShimsApp *AppAt(int app) {
    return (app >= 0 && app < atomic_load(&gAppCount)) ? gApps[app] : nil;
}

/// Called for every stack frame of every class lookup, NSBundle.mainBundle call… so it must be quick: one range
/// check over all guest images first (most addresses are system code, outside it), then the image found last.
static _Atomic uintptr_t gGuestLow = UINTPTR_MAX, gGuestHigh = 0;
static _Atomic uint32_t gLastImage;

static const GuestImage *ImageOf(uintptr_t address) {
    address &= 0x0000000FFFFFFFFFULL;      // drop pointer-authentication bits
    if (address < atomic_load(&gGuestLow) || address >= atomic_load(&gGuestHigh)) return NULL;
    uint32_t count = atomic_load(&gImageCount), last = atomic_load(&gLastImage);
    if (last < count && address >= gImages[last].start && address < gImages[last].end) return &gImages[last];
    for (uint32_t i = 0; i < count; i++) {
        if (address >= gImages[i].start && address < gImages[i].end) {
            atomic_store(&gLastImage, i);
            return &gImages[i];
        }
    }
    return NULL;
}

static int CurrentApp(void) { return gLoadingApp >= 0 ? gLoadingApp : gActiveApp; }

/// Walks the frame-pointer chain of the current thread; `first` is the immediate caller's return address.
static int AppFromStack(uintptr_t first) {
    const GuestImage *image = ImageOf(first);
    if (image && image->executable) return image->app;
    int framework = image ? image->app : -1;
    pthread_t thread = pthread_self();
    uintptr_t top = (uintptr_t)pthread_get_stackaddr_np(thread);
    uintptr_t bottom = top - pthread_get_stacksize_np(thread);
    uintptr_t fp = (uintptr_t)__builtin_frame_address(0);
    for (int depth = 0; depth < 48 && fp >= bottom && fp + 16 <= top && (fp & 0xF) == 0; depth++) {
        uintptr_t next = ((uintptr_t *)fp)[0];
        const GuestImage *frame = ImageOf(((uintptr_t *)fp)[1]);
        if (frame) {
            if (frame->executable) return frame->app;
            if (framework < 0) framework = frame->app;
        }
        if (next <= fp) break;
        fp = next;
    }
    return framework;
}

BOOL GuestShimsIsGuestCode(const void *address) { return ImageOf((uintptr_t)address) != NULL; }

int GuestShimsCallerApp(BOOL fallback) {
    int app = AppFromStack((uintptr_t)__builtin_return_address(0));
    return (app < 0 && fallback) ? CurrentApp() : app;
}

/// The app a hook should answer for: from the stack, else the current app. With a single app, that app.
#define ANSWERING_APP() (atomic_load(&gAppCount) == 1 ? 0 : ({ \
    int _app = AppFromStack((uintptr_t)__builtin_return_address(0)); _app >= 0 ? _app : CurrentApp(); }))

// MARK: - 1. Keychain

static OSStatus (*gCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*gAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*gUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*gDelete)(CFDictionaryRef);

/// The dictionary without kSecAttrAccessGroup (retained; the caller releases it).
static CFDictionaryRef WithoutAccessGroup(CFDictionaryRef dictionary) {
    if (!dictionary || !CFDictionaryContainsKey(dictionary, kSecAttrAccessGroup)) {
        return dictionary ? CFRetain(dictionary) : NULL;
    }
    CFMutableDictionaryRef copy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, dictionary);
    CFDictionaryRemoveValue(copy, kSecAttrAccessGroup);
    return copy;
}

static OSStatus ShimSecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    CFDictionaryRef q = WithoutAccessGroup(query);
    OSStatus status = gCopyMatching(q, result);
    if (q) CFRelease(q);
    return status;
}

static OSStatus ShimSecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    CFDictionaryRef a = WithoutAccessGroup(attributes);
    OSStatus status = gAdd(a, result);
    if (a) CFRelease(a);
    return status;
}

static OSStatus ShimSecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributes) {
    CFDictionaryRef q = WithoutAccessGroup(query), a = WithoutAccessGroup(attributes);
    OSStatus status = gUpdate(q, a);
    if (q) CFRelease(q);
    if (a) CFRelease(a);
    return status;
}

static OSStatus ShimSecItemDelete(CFDictionaryRef query) {
    CFDictionaryRef q = WithoutAccessGroup(query);
    OSStatus status = gDelete(q);
    if (q) CFRelease(q);
    return status;
}

// MARK: - 2. main() → UIApplicationMain

static BOOL gMainCalled;
static NSString *gMainPrincipal, *gMainDelegate;

void GuestShimsResetMainCall(void) { gMainCalled = NO; gMainPrincipal = nil; gMainDelegate = nil; }
BOOL GuestShimsMainCalled(void) { return gMainCalled; }
NSString *GuestShimsMainPrincipalClass(void) { return gMainPrincipal; }
NSString *GuestShimsMainDelegateClass(void) { return gMainDelegate; }

static int ShimUIApplicationMain(int argc, char **argv, NSString *principal, NSString *delegate) {
    gMainCalled = YES;
    gMainPrincipal = [principal copy];
    gMainDelegate = [delegate copy];
    // UIApplicationMain never returns in a real launch, and code after it may assume so: unwind back to
    // GuestRuntime instead of returning.
    @throw [NSException exceptionWithName:GuestShimsMainReached reason:@"UIApplicationMain" userInfo:nil];
}

// MARK: - 3. Main bundle, exit()

static CFBundleRef (*gGetMainBundle)(void);

static CFBundleRef ShimCFBundleGetMainBundle(void) {
    GuestShimsApp *app = AppAt(ANSWERING_APP());
    if (!app) return gGetMainBundle();
    @synchronized (app) {
        if (!app.cfBundle) app.cfBundle = CFBundleCreate(kCFAllocatorDefault, (__bridge CFURLRef)app.bundle.bundleURL);
    }
    return app.cfBundle ?: gGetMainBundle();
}

static void ShimExit(int code) {
    CrashReporterRecordExit(code, __builtin_return_address(0));
    exit(code);
}

static void Shim_Exit(int code) {
    CrashReporterRecordExit(code, __builtin_return_address(0));
    _exit(code);
}

// MARK: - Process-wide hooks, kept to the app that installed them

// Some apps install hooks that the whole process shares: a "class not found" hook (objc_setHook_getClass, used to
// load parts of an app lazily) or listeners for every library dyld loads. Alone in its process that is harmless;
// here the other apps' code runs through them too, and an app that does not recognise what it sees may abort
// (Facebook's hook took iDesk down while YouTube's tweaks were loading). Each hook a guest installs is wrapped in
// a slot that remembers the app: the class hook only answers that app's lookups, the listeners only hear about
// that app's own libraries. Past the last slot, hooks are installed as they are.

#define HOOK_SLOTS(X) X(0) X(1) X(2) X(3) X(4) X(5) X(6) X(7) X(8) X(9) X(10) X(11) X(12) X(13) X(14) X(15)
#define HOOK_SLOT_COUNT 16

typedef BOOL (*ClassHook)(const char *name, Class *outClass);
static struct { ClassHook hook; ClassHook next; int app; } gClassHooks[HOOK_SLOT_COUNT];
static _Atomic int gClassHookCount;

static BOOL RunClassHook(int slot, const char *name, Class *outClass) {
    int caller = AppFromStack(0);
    if (caller < 0) caller = CurrentApp();
    if (caller == gClassHooks[slot].app) return gClassHooks[slot].hook(name, outClass);
    ClassHook next = gClassHooks[slot].next;
    return next ? next(name, outClass) : NO;
}

#define CLASS_HOOK(n) static BOOL ClassHook##n(const char *name, Class *out) { return RunClassHook(n, name, out); }
HOOK_SLOTS(CLASS_HOOK)
#define CLASS_HOOK_NAME(n) ClassHook##n,
static const ClassHook kClassHookSlots[HOOK_SLOT_COUNT] = { HOOK_SLOTS(CLASS_HOOK_NAME) };

static void ShimSetHookGetClass(ClassHook hook, ClassHook *outOldValue) {
    int app = AppFromStack((uintptr_t)__builtin_return_address(0));
    if (app < 0) app = CurrentApp();
    int slot = app < 0 || !hook ? HOOK_SLOT_COUNT : atomic_fetch_add(&gClassHookCount, 1);
    if (slot >= HOOK_SLOT_COUNT) return objc_setHook_getClass(hook, outOldValue);
    gClassHooks[slot].hook = hook;
    gClassHooks[slot].app = app;
    objc_setHook_getClass(kClassHookSlots[slot], &gClassHooks[slot].next);
    if (outOldValue) *outOldValue = gClassHooks[slot].next;     // the app's hook passes on what it does not handle
}

/// Whether a library belongs to another guest app than `app` (system libraries and iDesk belong to everyone).
static BOOL IsOtherAppsImage(const void *header, int app) {
    const GuestImage *image = ImageOf((uintptr_t)header);
    return image && image->app != app;
}

typedef void (*ImageCallback)(const struct mach_header *header, intptr_t slide);
static struct { ImageCallback callback; int app; } gAddImage[HOOK_SLOT_COUNT], gRemoveImage[HOOK_SLOT_COUNT];
static _Atomic int gAddImageCount, gRemoveImageCount;

#define ADD_IMAGE(n) static void AddImage##n(const struct mach_header *h, intptr_t slide) { \
    if (!IsOtherAppsImage(h, gAddImage[n].app)) gAddImage[n].callback(h, slide); }
#define REMOVE_IMAGE(n) static void RemoveImage##n(const struct mach_header *h, intptr_t slide) { \
    if (!IsOtherAppsImage(h, gRemoveImage[n].app)) gRemoveImage[n].callback(h, slide); }
HOOK_SLOTS(ADD_IMAGE)
HOOK_SLOTS(REMOVE_IMAGE)
#define ADD_IMAGE_NAME(n) AddImage##n,
#define REMOVE_IMAGE_NAME(n) RemoveImage##n,
static const ImageCallback kAddImageSlots[HOOK_SLOT_COUNT] = { HOOK_SLOTS(ADD_IMAGE_NAME) };
static const ImageCallback kRemoveImageSlots[HOOK_SLOT_COUNT] = { HOOK_SLOTS(REMOVE_IMAGE_NAME) };

static void ShimRegisterAddImage(ImageCallback callback) {
    int app = AppFromStack((uintptr_t)__builtin_return_address(0));
    if (app < 0) app = CurrentApp();
    int slot = app < 0 || !callback ? HOOK_SLOT_COUNT : atomic_fetch_add(&gAddImageCount, 1);
    if (slot >= HOOK_SLOT_COUNT) return _dyld_register_func_for_add_image(callback);
    gAddImage[slot].callback = callback;
    gAddImage[slot].app = app;
    _dyld_register_func_for_add_image(kAddImageSlots[slot]);
}

static void ShimRegisterRemoveImage(ImageCallback callback) {
    int app = AppFromStack((uintptr_t)__builtin_return_address(0));
    if (app < 0) app = CurrentApp();
    int slot = app < 0 || !callback ? HOOK_SLOT_COUNT : atomic_fetch_add(&gRemoveImageCount, 1);
    if (slot >= HOOK_SLOT_COUNT) return _dyld_register_func_for_remove_image(callback);
    gRemoveImage[slot].callback = callback;
    gRemoveImage[slot].app = app;
    _dyld_register_func_for_remove_image(kRemoveImageSlots[slot]);
}

typedef void (*LoadImageFunc)(const struct mach_header *header);
static struct { LoadImageFunc func; int app; } gLoadImage[HOOK_SLOT_COUNT];
static _Atomic int gLoadImageCount;

#define LOAD_IMAGE(n) static void LoadImage##n(const struct mach_header *h) { \
    if (!IsOtherAppsImage(h, gLoadImage[n].app)) gLoadImage[n].func(h); }
HOOK_SLOTS(LOAD_IMAGE)
#define LOAD_IMAGE_NAME(n) LoadImage##n,
static const LoadImageFunc kLoadImageSlots[HOOK_SLOT_COUNT] = { HOOK_SLOTS(LOAD_IMAGE_NAME) };

static void ShimAddLoadImageFunc(LoadImageFunc func) {
    int app = AppFromStack((uintptr_t)__builtin_return_address(0));
    if (app < 0) app = CurrentApp();
    int slot = app < 0 || !func ? HOOK_SLOT_COUNT : atomic_fetch_add(&gLoadImageCount, 1);
    if (slot >= HOOK_SLOT_COUNT) return objc_addLoadImageFunc(func);
    gLoadImage[slot].func = func;
    gLoadImage[slot].app = app;
    objc_addLoadImageFunc(kLoadImageSlots[slot]);
}

// MARK: - Libraries of other apps

// Bundled apps share one folder: each one's frameworks and tweak libraries are all in iDesk.app/Frameworks. Tweak
// loaders (LoadControl and the like) open every library they find next to themselves, so one app would load the
// others' tweaks too, which hook classes they know nothing about (YouTube's tweaks then reached Facebook's code
// and took iDesk down). A guest's dlopen of a library that another app brought is refused; dlerror() says why.

static NSString *gSharedFolder;                  // iDesk.app/Frameworks, symlinks resolved
static NSSet<NSString *> *gGuestLibraries;       // every name listed by a bundled app

static void LoadSharedLibraryList(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char resolved[PATH_MAX];
        NSString *folder = gHostBundle.privateFrameworksPath;
        if (!folder || !realpath(folder.fileSystemRepresentation, resolved)) return;
        gSharedFolder = [NSString stringWithUTF8String:resolved];
        NSMutableSet<NSString *> *names = [NSMutableSet set];
        for (NSString *item in [NSFileManager.defaultManager contentsOfDirectoryAtPath:gSharedFolder error:nil]) {
            if (![item hasPrefix:@"iDeskGuest_"]) continue;
            NSString *list = [NSString stringWithContentsOfFile:[[gSharedFolder stringByAppendingPathComponent:item]
                                                                    stringByAppendingPathComponent:@"iDeskFrameworks.txt"]
                                                       encoding:NSUTF8StringEncoding error:nil];
            for (NSString *name in [list componentsSeparatedByString:@"\n"]) if (name.length) [names addObject:name];
        }
        gGuestLibraries = names;
    });
}

static NSSet<NSString *> *OwnLibraries(NSBundle *bundle) {
    NSString *list = [NSString stringWithContentsOfFile:[bundle.bundlePath stringByAppendingPathComponent:@"iDeskFrameworks.txt"]
                                               encoding:NSUTF8StringEncoding error:nil];
    if (!list) return nil;
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (NSString *name in [list componentsSeparatedByString:@"\n"]) if (name.length) [names addObject:name];
    return names;
}

/// The item of iDesk.app/Frameworks that `path` is in, when another guest app put it there (or it is another app).
static NSString *OtherAppsLibrary(const char *path, int app) {
    GuestShimsApp *caller = AppAt(app);
    if (!path || path[0] != '/' || !caller.ownLibraries) return nil;
    LoadSharedLibraryList();
    char resolved[PATH_MAX];
    if (!gSharedFolder || !realpath(path, resolved)) return nil;        // not there: dlopen fails by itself
    NSString *full = [NSString stringWithUTF8String:resolved];
    NSString *prefix = [gSharedFolder stringByAppendingString:@"/"];
    if (![full hasPrefix:prefix]) return nil;
    NSString *top = [[full substringFromIndex:prefix.length] pathComponents].firstObject;
    if (!top.length) return nil;
    if ([top hasPrefix:@"iDeskGuest_"]) return [top isEqualToString:caller.bundle.bundlePath.lastPathComponent] ? nil : top;
    return [gGuestLibraries containsObject:top] && ![caller.ownLibraries containsObject:top] ? top : nil;
}

// A bundled app's frameworks were moved out of its folder: "<app>/Frameworks/X" is "iDesk.app/Frameworks/X" now.
// The load commands of its executable were rewritten when it was packaged, but an app that builds the path itself
// (its bundle path + "/Frameworks/…", as Facebook does for the parts it loads later) would not find them and quit.
// Such a path, when nothing is there, is pointed to the moved copy.
static NSString *MovedFrameworkPath(NSString *path) {
    if (![path containsString:@"/iDeskGuest_"] || ![path containsString:@".framework/Frameworks/"]) return nil;
    NSArray<NSString *> *parts = path.pathComponents;
    for (NSUInteger i = 0; i + 2 < parts.count; i++) {
        if (![parts[i] hasPrefix:@"iDeskGuest_"] || ![parts[i].pathExtension isEqualToString:@"framework"]
            || ![parts[i + 1] isEqualToString:@"Frameworks"]) continue;
        NSArray *rest = [parts subarrayWithRange:NSMakeRange(i + 2, parts.count - i - 2)];
        NSString *moved = [NSString pathWithComponents:[[parts subarrayWithRange:NSMakeRange(0, i)] arrayByAddingObjectsFromArray:rest]];
        NSFileManager *fm = NSFileManager.defaultManager;
        return ![fm fileExistsAtPath:path] && [fm fileExistsAtPath:moved] ? moved : nil;
    }
    return nil;
}

static id (*gBundleInitWithPath)(id, SEL, NSString *);
static id ShimBundleInitWithPath(id self, SEL _cmd, NSString *path) {
    NSString *moved = path ? MovedFrameworkPath(path) : nil;
    return gBundleInitWithPath(self, _cmd, moved ?: path);
}

/// A bundled app looking for one of its frameworks as a resource of its own bundle ("FBSharedFramework" of type
/// "framework" in "Frameworks", as Facebook does before it loads the parts it needs later): the framework was moved to
/// iDesk.app/Frameworks when the app was packaged, so the lookup finds nothing and Facebook stops ("Failed to load
/// dynamic library"). When the app's own folder has nothing there, the moved copy is answered.
static NSString *MovedResource(NSBundle *bundle, NSString *name, NSString *ext, NSString *directory) {
    if (!name.length || ![directory hasPrefix:@"Frameworks"] || ![bundle.bundlePath.lastPathComponent hasPrefix:@"iDeskGuest_"]) return nil;
    NSString *file = ext.length ? [name stringByAppendingPathExtension:ext] : name;
    NSString *inside = [[bundle.bundlePath stringByAppendingPathComponent:directory] stringByAppendingPathComponent:file];
    return MovedFrameworkPath(inside);
}

static NSString *(*gPathForResourceInDirectory)(id, SEL, NSString *, NSString *, NSString *);
static NSString *ShimPathForResourceInDirectory(NSBundle *self, SEL _cmd, NSString *name, NSString *ext, NSString *directory) {
    NSString *found = gPathForResourceInDirectory(self, _cmd, name, ext, directory);
    return found ?: MovedResource(self, name, ext, directory);
}

static NSURL *(*gURLForResourceInDirectory)(id, SEL, NSString *, NSString *, NSString *);
static NSURL *ShimURLForResourceInDirectory(NSBundle *self, SEL _cmd, NSString *name, NSString *ext, NSString *directory) {
    NSURL *found = gURLForResourceInDirectory(self, _cmd, name, ext, directory);
    if (found) return found;
    NSString *moved = MovedResource(self, name, ext, directory);
    return moved ? [NSURL fileURLWithPath:moved] : nil;
}

/// -[NSBundle initWithURL:] (and +bundleWithURL:) with nil: NSBundle throws, which ends iDesk. Inside iDesk an
/// app's resource is sometimes not where it expects it (TikTok asks for one of its bundles by URL at launch and
/// gets nil): answer nil, as for a path that does not exist, and the app goes on without it.
static id (*gBundleInitWithURL)(id, SEL, NSURL *);
static id ShimBundleInitWithURL(id self, SEL _cmd, NSURL *url) {
    if (!url) {
        NSLog(@"[iDesk] an app asked for a bundle with no URL: answered nil instead of raising");
        return nil;
    }
    if (url.isFileURL) {
        NSString *moved = MovedFrameworkPath(url.path);
        if (moved) url = [NSURL fileURLWithPath:moved];
    }
    return gBundleInitWithURL(self, _cmd, url);
}

/// -[MTLDevice newLibraryWithFile:error:] with nil or a file that is not there: Metal asserts and ends iDesk (TikTok
/// asks for a .metallib of its own this way, found by a lookup that comes back empty inside iDesk). A moved framework's
/// path is pointed to the moved copy; otherwise Metal's documented failure is answered: nil and an error.
/// The library's file, or the moved framework's copy; nil (and Metal's "not found" error) when neither is there.
static NSString *ExistingMetalLibrary(NSString *path, NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (path.length && ![fm fileExistsAtPath:path]) path = MovedFrameworkPath(path) ?: path;
    if (path.length && [fm fileExistsAtPath:path]) return path;
    NSLog(@"[iDesk] an app asked Metal for a library that is not there (%@): answered nil", path ?: @"no path");
    if (error) *error = [NSError errorWithDomain:MTLLibraryErrorDomain code:MTLLibraryErrorFileNotFound
                                        userInfo:@{NSLocalizedDescriptionKey: @"Metal library not found"}];
    return nil;
}

static id (*gNewLibraryWithFile)(id, SEL, NSString *, NSError **);
static id ShimNewLibraryWithFile(id self, SEL _cmd, NSString *path, NSError **error) {
    NSString *found = ExistingMetalLibrary(path, error);
    return found ? gNewLibraryWithFile(self, _cmd, found, error) : nil;
}

static id (*gNewLibraryWithURL)(id, SEL, NSURL *, NSError **);
static id ShimNewLibraryWithURL(id self, SEL _cmd, NSURL *url, NSError **error) {
    if (url && !url.isFileURL) return gNewLibraryWithURL(self, _cmd, url, error);
    NSString *found = ExistingMetalLibrary(url.path, error);
    return found ? gNewLibraryWithURL(self, _cmd, [NSURL fileURLWithPath:found], error) : nil;
}

// MARK: Attributed strings out of range

// Facebook's feed builds a story's subtitle as an attributed string and, inside iDesk, sometimes asks for the
// attributes of a character past its end (NSRangeException "NSMutableRLEArray objectAtIndex:effectiveRange::
// Out of bounds"), which ends iDesk with every app in it. A read past the end answers "no attributes" and a change
// past the end is cut to the string, as for an empty string, instead of throwing.
enum { kAttrClasses = 3 };
static Class gAttrClass[kAttrClasses];
static IMP gAttrsAt[kAttrClasses], gAttrAt[kAttrClasses], gAddAttr[kAttrClasses], gAddAttrs[kAttrClasses],
           gSetAttrs[kAttrClasses], gRemoveAttr[kAttrClasses];

static int AttrIndex(id self) {
    Class c = object_getClass(self);
    for (; c; c = class_getSuperclass(c))
        for (int i = 0; i < kAttrClasses; i++) if (gAttrClass[i] == c) return i;
    return -1;
}

static void NoteOutOfRange(const char *what) {
    static _Atomic int logged;
    if (atomic_fetch_add(&logged, 1) < 5) NSLog(@"[iDesk] an app used an attributed string out of range (%s): ignored", what);
}

/// The range cut to the string; NO when nothing of it is in the string.
static BOOL ClampRange(NSAttributedString *self, NSRange *range) {
    NSUInteger length = self.length;
    if (range->location > length) return NO;
    if (range->length > length - range->location) range->length = length - range->location;
    return YES;
}

static NSDictionary *ShimAttrsAt(NSAttributedString *self, SEL _cmd, NSUInteger index, NSRangePointer effective) {
    int i = AttrIndex(self);
    if (index >= self.length) {
        NoteOutOfRange("attributesAtIndex");
        if (effective) *effective = NSMakeRange(index, 0);
        return @{};
    }
    return ((NSDictionary *(*)(id, SEL, NSUInteger, NSRangePointer))gAttrsAt[i])(self, _cmd, index, effective);
}

static id ShimAttrAt(NSAttributedString *self, SEL _cmd, NSAttributedStringKey key, NSUInteger index, NSRangePointer effective) {
    int i = AttrIndex(self);
    if (index >= self.length) {
        NoteOutOfRange("attribute:atIndex");
        if (effective) *effective = NSMakeRange(index, 0);
        return nil;
    }
    return ((id (*)(id, SEL, NSAttributedStringKey, NSUInteger, NSRangePointer))gAttrAt[i])(self, _cmd, key, index, effective);
}

static void ShimAddAttr(NSMutableAttributedString *self, SEL _cmd, NSAttributedStringKey key, id value, NSRange range) {
    int i = AttrIndex(self);
    NSRange r = range;
    if (!ClampRange(self, &r)) { NoteOutOfRange("addAttribute"); return; }
    if (r.length != range.length) NoteOutOfRange("addAttribute");
    ((void (*)(id, SEL, NSAttributedStringKey, id, NSRange))gAddAttr[i])(self, _cmd, key, value, r);
}

static void ShimAddAttrs(NSMutableAttributedString *self, SEL _cmd, NSDictionary *attrs, NSRange range) {
    int i = AttrIndex(self);
    NSRange r = range;
    if (!ClampRange(self, &r)) { NoteOutOfRange("addAttributes"); return; }
    ((void (*)(id, SEL, NSDictionary *, NSRange))gAddAttrs[i])(self, _cmd, attrs, r);
}

static void ShimSetAttrs(NSMutableAttributedString *self, SEL _cmd, NSDictionary *attrs, NSRange range) {
    int i = AttrIndex(self);
    NSRange r = range;
    if (!ClampRange(self, &r)) { NoteOutOfRange("setAttributes"); return; }
    ((void (*)(id, SEL, NSDictionary *, NSRange))gSetAttrs[i])(self, _cmd, attrs, r);
}

static void ShimRemoveAttr(NSMutableAttributedString *self, SEL _cmd, NSAttributedStringKey key, NSRange range) {
    int i = AttrIndex(self);
    NSRange r = range;
    if (!ClampRange(self, &r)) { NoteOutOfRange("removeAttribute"); return; }
    ((void (*)(id, SEL, NSAttributedStringKey, NSRange))gRemoveAttr[i])(self, _cmd, key, r);
}

static void GuardAttributedStrings(void) {
    const char *names[kAttrClasses] = { "NSConcreteMutableAttributedString", "NSConcreteAttributedString", "__NSCFAttributedString" };
    for (int i = 0; i < kAttrClasses; i++) {
        Class c = objc_getClass(names[i]);
        if (!c) continue;
        IMP attrsAt = GuestShimsReplaceMethod(c, @selector(attributesAtIndex:effectiveRange:), NO, (IMP)ShimAttrsAt);
        IMP attrAt = GuestShimsReplaceMethod(c, @selector(attribute:atIndex:effectiveRange:), NO, (IMP)ShimAttrAt);
        // Each shim calls the original of the class it was put on: only keep a class whose originals were found.
        if (!attrsAt || !attrAt) continue;
        gAttrClass[i] = c;
        gAttrsAt[i] = attrsAt;
        gAttrAt[i] = attrAt;
        if ([c instancesRespondToSelector:@selector(addAttribute:value:range:)]) {
            gAddAttr[i] = GuestShimsReplaceMethod(c, @selector(addAttribute:value:range:), NO, (IMP)ShimAddAttr);
            gAddAttrs[i] = GuestShimsReplaceMethod(c, @selector(addAttributes:range:), NO, (IMP)ShimAddAttrs);
            gSetAttrs[i] = GuestShimsReplaceMethod(c, @selector(setAttributes:range:), NO, (IMP)ShimSetAttrs);
            gRemoveAttr[i] = GuestShimsReplaceMethod(c, @selector(removeAttribute:range:), NO, (IMP)ShimRemoveAttr);
        }
    }
}

typedef void *(*DlopenFrom)(const char *path, int mode, void *addressInCaller);
static DlopenFrom gDlopenFrom;     // dyld's dlopen on behalf of a caller (its @loader_path and @rpath)

static void *ShimDlopen(const char *path, int mode) {
    void *returnAddress = __builtin_return_address(0);
    int app = gLoadingApp >= 0 ? gLoadingApp : AppFromStack((uintptr_t)returnAddress);
    if (app < 0) app = gActiveApp;
    NSString *moved = path && path[0] == '/' ? MovedFrameworkPath([NSString stringWithUTF8String:path] ?: @"") : nil;
    if (moved) path = moved.fileSystemRepresentation;
    NSString *other = OtherAppsLibrary(path, app);
    if (other) {
        NSDictionary *info = AppAt(app).bundle.infoDictionary;
        NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: AppAt(app).bundle.bundlePath.lastPathComponent;
        NSLog(@"[iDesk] %@ did not load %@: it belongs to another app", name, other);
        return dlopen("/iDesk refused a library of another app", mode);     // fails, so dlerror() explains
    }
    return gDlopenFrom(path, mode, returnAddress);
}

// MARK: - Rewriting symbol pointers

// Old tweak libraries import the C++ runtime of libstdc++, which iOS removed (libc++ has its own, in std::__1).
// Once ImportWeakener made them optional dyld leaves them NULL, and calling one crashes at once (often in a static
// initializer, before the app runs). They get a function that does nothing and returns 0, or zeroed storage.
// Only those: any other NULL import is an API the app checks for itself (a class or function of a newer iOS)
// and must stay NULL.
static long MissingFunction(void) { return 0; }
static uint8_t gMissingData[64 * 1024];

static BOOL IsRemovedLibstdcxx(const char *name) {
    return !strncmp(name, "__Z", 3) && !strstr(name, "St3__1");
}

static BOOL LooksLikeData(const char *name) {
    return !strncmp(name, "__ZTV", 5) || !strncmp(name, "__ZTI", 5) || !strncmp(name, "__ZTS", 5)
        || strstr(name, "storage") != NULL;
}

static unsigned gStubbed;

typedef struct { const char *name; void *replacement; } Rebinding;

static const Rebinding kRebindings[] = {
    { "_SecItemCopyMatching", (void *)ShimSecItemCopyMatching },
    { "_SecItemAdd", (void *)ShimSecItemAdd },
    { "_SecItemUpdate", (void *)ShimSecItemUpdate },
    { "_SecItemDelete", (void *)ShimSecItemDelete },
    { "_UIApplicationMain", (void *)ShimUIApplicationMain },
    { "_CFBundleGetMainBundle", (void *)ShimCFBundleGetMainBundle },
    { "_exit", (void *)ShimExit },
    { "__exit", (void *)Shim_Exit },
    { "_objc_setHook_getClass", (void *)ShimSetHookGetClass },
    { "__dyld_register_func_for_add_image", (void *)ShimRegisterAddImage },
    { "__dyld_register_func_for_remove_image", (void *)ShimRegisterRemoveImage },
    { "_objc_addLoadImageFunc", (void *)ShimAddLoadImageFunc },
    { "_dlopen", (void *)ShimDlopen },          // only when dyld has dlopen_from (see RebindSection)
};

static void RebindSection(const struct section_64 *section, intptr_t slide, const struct nlist_64 *symbols,
                          const char *strings, const uint32_t *indirect) {
    const uint32_t *indices = indirect + section->reserved1;
    void **pointers = (void **)(slide + section->addr);
    size_t count = section->size / sizeof(void *);
    for (size_t i = 0; i < count; i++) {
        uint32_t index = indices[i];
        if (index == INDIRECT_SYMBOL_ABS || index == INDIRECT_SYMBOL_LOCAL ||
            index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
        const char *name = strings + symbols[index].n_un.n_strx;
        if (name[0] != '_') continue;
        if (!pointers[i] && IsRemovedLibstdcxx(name)) {
            uintptr_t page = (uintptr_t)&pointers[i] & ~(uintptr_t)(PAGE_SIZE - 1);
            if (mprotect((void *)page, PAGE_SIZE, PROT_READ | PROT_WRITE) == 0) {
                pointers[i] = LooksLikeData(name) ? (void *)gMissingData : (void *)MissingFunction;
                gStubbed++;
            }
            continue;
        }
        for (size_t r = 0; r < sizeof(kRebindings) / sizeof(kRebindings[0]); r++) {
            if (strcmp(name, kRebindings[r].name) != 0) continue;
            if (pointers[i] == kRebindings[r].replacement) break;
            if (kRebindings[r].replacement == (void *)ShimDlopen && !gDlopenFrom) break;
            // __DATA_CONST is read-only once dyld is done with it: open the page for writing.
            uintptr_t page = (uintptr_t)&pointers[i] & ~(uintptr_t)(PAGE_SIZE - 1);
            if (mprotect((void *)page, PAGE_SIZE, PROT_READ | PROT_WRITE) == 0) {
                pointers[i] = kRebindings[r].replacement;
            }
            break;
        }
    }
}

static void RebindImage(const struct mach_header_64 *header, intptr_t slide) {
    const struct segment_command_64 *linkedit = NULL;
    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysymtab = NULL;
    const uint8_t *p = (const uint8_t *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmd == LC_SEGMENT_64 && !strcmp(((const struct segment_command_64 *)lc)->segname, SEG_LINKEDIT)) {
            linkedit = (const struct segment_command_64 *)lc;
        } else if (lc->cmd == LC_SYMTAB) {
            symtab = (const struct symtab_command *)lc;
        } else if (lc->cmd == LC_DYSYMTAB) {
            dysymtab = (const struct dysymtab_command *)lc;
        }
        p += lc->cmdsize;
    }
    if (!linkedit || !symtab || !dysymtab || !dysymtab->nindirectsyms) return;

    uintptr_t base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
    const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
    const char *strings = (const char *)(base + symtab->stroff);
    const uint32_t *indirect = (const uint32_t *)(base + dysymtab->indirectsymoff);

    p = (const uint8_t *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)p;
        p += lc->cmdsize;
        if (lc->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *segment = (const struct segment_command_64 *)lc;
        if (strncmp(segment->segname, "__DATA", 6) != 0 && strcmp(segment->segname, "__AUTH_CONST") != 0) continue;
        const struct section_64 *sections = (const struct section_64 *)(segment + 1);
        for (uint32_t s = 0; s < segment->nsects; s++) {
            uint32_t type = sections[s].flags & SECTION_TYPE;
            if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) {
                RebindSection(&sections[s], slide, symbols, strings, indirect);
            }
        }
    }
}

static BOOL gActive;

/// Every image added once a guest starts loading that is not a system library belongs to a guest: the one being
/// loaded, or (a library the app opens later by itself) the active one.
static void ImageAdded(const struct mach_header *header, intptr_t slide) {
    if (!gActive || !header || header->magic != MH_MAGIC_64) return;
    if (header->flags & 0x80000000) return;                       // MH_DYLIB_IN_CACHE: a system library
    if (header == _dyld_get_image_header(0)) return;              // iDesk's own executable
    Dl_info info;
    if (!dladdr(header, &info) || !info.dli_fname) return;
    if (strstr(info.dli_fname, "/iDesk.debug.dylib")) return;
    // A library opened later (not while an app loads) belongs to the app whose code opened it.
    int owner = gLoadingApp;
    if (owner < 0) owner = AppFromStack(0);
    if (owner < 0) owner = gActiveApp;
    GuestShimsApp *app = AppAt(owner);
    uint32_t index = atomic_load(&gImageCount);
    if (app && index < sizeof(gImages) / sizeof(gImages[0])) {
        GuestImage image = { 0, 0, owner, NO };
        MachOTextRange(header, slide, &image.start, &image.end);
        size_t length = strlen(info.dli_fname), suffix = strlen(app.executableSuffix);
        image.executable = length >= suffix && !strcmp(info.dli_fname + length - suffix, app.executableSuffix);
        gImages[index] = image;
        atomic_store(&gImageCount, index + 1);
        if (image.start < atomic_load(&gGuestLow)) atomic_store(&gGuestLow, image.start);
        if (image.end > atomic_load(&gGuestHigh)) atomic_store(&gGuestHigh, image.end);
    }
    unsigned stubbed = gStubbed;
    RebindImage((const struct mach_header_64 *)header, slide);
    if (gStubbed != stubbed) {
        const char *file = strrchr(info.dli_fname, '/');
        NSLog(@"[iDesk] %s: %u libstdc++ imports now do nothing", file ? file + 1 : info.dli_fname, gStubbed - stubbed);
    }
}

// MARK: - Objective-C hooks

IMP GuestShimsReplaceMethod(Class cls, SEL selector, BOOL classMethod, IMP replacement) {
    if (!cls) return NULL;
    Method m = classMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    if (!m) return NULL;
    Class owner = classMethod ? object_getClass(cls) : cls;
    // Add on the class itself first, so a method inherited from a superclass is not changed for everyone.
    if (class_addMethod(owner, selector, replacement, method_getTypeEncoding(m))) return method_getImplementation(m);
    return method_setImplementation(m, replacement);
}

// App Groups

static NSURL *(*gContainerURL)(id, SEL, NSString *);

static NSURL *ShimContainerURL(NSFileManager *self, SEL _cmd, NSString *group) {
    NSURL *url = gContainerURL(self, _cmd, group);
    if (url || !group.length) return url;
    NSURL *library = [self URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *safe = [group stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    url = [[library URLByAppendingPathComponent:@"GuestAppGroups" isDirectory:YES]
           URLByAppendingPathComponent:safe isDirectory:YES];
    [self createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

// Main bundle, app delegate, key window / windows: the asking app's own.

static NSBundle *(*gMainBundle)(id, SEL);
static NSString *(*gLocalized)(id, SEL, NSString *, NSString *, NSString *);
static NSString *(*gLocalizedIn)(id, SEL, NSString *, NSString *, NSString *, id);
static NSString *(*gLocalizedAmong)(id, SEL, NSString *, NSString *, NSString *, id);
static NSAttributedString *(*gAttributed)(id, SEL, NSString *, NSString *, NSString *);
static NSAttributedString *(*gAttributedIn)(id, SEL, NSString *, NSString *, NSString *, id);
static id (*gAppDelegate)(id, SEL);
static id (*gAppKeyWindow)(id, SEL);
static id (*gSceneKeyWindow)(id, SEL);
static NSArray *(*gAppWindows)(id, SEL);

static NSBundle *ShimMainBundle(id self, SEL _cmd) {
    return AppAt(ANSWERING_APP()).bundle ?: gMainBundle(self, _cmd);
}

static BOOL IsGuestBundle(NSBundle *bundle) {
    int count = atomic_load(&gAppCount);
    for (int i = 0; i < count; i++) if (gApps[i].bundle == bundle) return YES;
    return NO;
}

/// With a guest bundle standing in as the main bundle, iDesk's own interface would look its texts up there.
/// A key missing from the guest's Localizable table is looked up in iDesk's, in iDesk's own preferred language:
/// SwiftUI uses the variants that name a localization, chosen from the guest bundle (often only English).
static BOOL ShouldAskHost(NSBundle *bundle, NSString *key, NSString *value, NSString *table, NSString *text) {
    return key.length && bundle != gHostBundle && (!table.length || [table isEqualToString:@"Localizable"])
        && [text isEqualToString:value.length ? value : key] && IsGuestBundle(bundle);
}

static NSString *ShimLocalized(NSBundle *self, SEL _cmd, NSString *key, NSString *value, NSString *table) {
    NSString *text = gLocalized(self, _cmd, key, value, table);
    return ShouldAskHost(self, key, value, table, text) ? gLocalized(gHostBundle, _cmd, key, value, table) : text;
}

static NSString *ShimLocalizedIn(NSBundle *self, SEL _cmd, NSString *key, NSString *value, NSString *table, id localization) {
    NSString *text = gLocalizedIn(self, _cmd, key, value, table, localization);
    return ShouldAskHost(self, key, value, table, text)
        ? gLocalized(gHostBundle, @selector(localizedStringForKey:value:table:), key, value, table) : text;
}

/// SwiftUI's Text resolves keys as attributed strings (for Markdown).
static NSAttributedString *HostAttributed(NSString *key, NSString *value, NSString *table) {
    NSString *language = gHostBundle.preferredLocalizations.firstObject;
    return gAttributedIn(gHostBundle, NSSelectorFromString(@"localizedAttributedStringForKey:value:table:localization:"),
                         key, value, table, language);
}

static NSAttributedString *ShimAttributed(NSBundle *self, SEL _cmd, NSString *key, NSString *value, NSString *table) {
    NSAttributedString *text = gAttributed(self, _cmd, key, value, table);
    return ShouldAskHost(self, key, value, table, text.string) ? HostAttributed(key, value, table) : text;
}

static NSAttributedString *ShimAttributedIn(NSBundle *self, SEL _cmd, NSString *key, NSString *value, NSString *table,
                                            id localization) {
    NSAttributedString *text = gAttributedIn(self, _cmd, key, value, table, localization);
    return ShouldAskHost(self, key, value, table, text.string) ? HostAttributed(key, value, table) : text;
}

static NSString *ShimLocalizedAmong(NSBundle *self, SEL _cmd, NSString *key, NSString *value, NSString *table, id localizations) {
    NSString *text = gLocalizedAmong(self, _cmd, key, value, table, localizations);
    return ShouldAskHost(self, key, value, table, text)
        ? gLocalized(gHostBundle, @selector(localizedStringForKey:value:table:), key, value, table) : text;
}

/// Every guest's `UIApplication.shared.delegate as! AppDelegate` must find its own delegate.
static id ShimAppDelegate(id self, SEL _cmd) {
    if (atomic_load(&gAppCount) > 1) {
        int app = AppFromStack((uintptr_t)__builtin_return_address(0));
        id delegate = AppAt(app).delegate;
        if (delegate) return delegate;
    }
    return gAppDelegate(self, _cmd);
}

static id ShimAppKeyWindow(id self, SEL _cmd) {
    UIWindow *window = AppAt(AppFromStack((uintptr_t)__builtin_return_address(0))).window;
    return window ?: gAppKeyWindow(self, _cmd);
}

static id ShimSceneKeyWindow(id self, SEL _cmd) {
    UIWindow *window = AppAt(AppFromStack((uintptr_t)__builtin_return_address(0))).window;
    if (window && window.windowScene == self) return window;
    return gSceneKeyWindow(self, _cmd);
}

/// `UIApplication.shared.windows.first` is a common way to find "the" window: put the asking app's first.
static NSArray *ShimAppWindows(id self, SEL _cmd) {
    NSArray *windows = gAppWindows(self, _cmd);
    UIWindow *window = AppAt(AppFromStack((uintptr_t)__builtin_return_address(0))).window;
    if (!window || ![windows containsObject:window]) return windows;
    NSMutableArray *ordered = [windows mutableCopy];
    [ordered removeObject:window];
    [ordered insertObject:window atIndex:0];
    return ordered;
}

// An object that answers every message with nothing (0 / NO / nil, or itself for object results) and never calls
// back. Stands in for a system object the guest cannot get without an entitlement: the feature stays silent
// instead of crashing the app.

@interface IDeskInertObject : NSProxy
@property (nonatomic) Class model;
@end

@implementation IDeskInertObject

+ (instancetype)standingInFor:(Class)model {
    IDeskInertObject *object = [self alloc];
    object.model = model;
    return object;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [_model instanceMethodSignatureForSelector:selector] ?: [NSMethodSignature signatureWithObjCTypes:"v@:"];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    NSMethodSignature *signature = invocation.methodSignature;
    NSUInteger length = signature.methodReturnLength;
    if (!length) return;
    if (signature.methodReturnType[0] == '@') {
        __unsafe_unretained id me = self;
        [invocation setReturnValue:&me];
        return;
    }
    void *zero = calloc(1, length);
    [invocation setReturnValue:zero];
    free(zero);
}

- (BOOL)respondsToSelector:(SEL)selector { return [_model instancesRespondToSelector:selector]; }
- (BOOL)isKindOfClass:(Class)cls { return [_model isSubclassOfClass:cls]; }
- (NSString *)description { return [NSString stringWithFormat:@"<iDesk inert %@>", _model]; }

@end

// CloudKit
//
// iDesk never has the iCloud entitlement (the signing app signs it with the user's certificate), and CloudKit
// throws about it inside dispatch_once, where libdispatch turns any exception into a crash. So never ask
// CloudKit: hand out an inert container straight away.

static id ShimDefaultContainer(id self, SEL _cmd) {
    static id inert;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inert = [IDeskInertObject standingInFor:NSClassFromString(@"CKContainer")];
        NSLog(@"[iDesk] CloudKit is unavailable to the guest app: using an inert container");
    });
    return inert;
}

static id ShimContainerWithIdentifier(id self, SEL _cmd, NSString *identifier) {
    return ShimDefaultContainer(self, _cmd);
}

// HealthKit: likewise no entitlement, and the request throws. Answer it as denied.

typedef void (^AuthorizationCompletion)(BOOL, NSError *);

static void ShimHealthAuthorization(id self, SEL _cmd, id share, id read, AuthorizationCompletion completion) {
    NSError *error = [NSError errorWithDomain:@"com.apple.healthkit" code:4   // HKErrorAuthorizationDenied
                                     userInfo:@{NSLocalizedDescriptionKey: @"HealthKit is not available in iDesk."}];
    if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
}

// BackgroundTasks

static BOOL ShimRegisterTask(id self, SEL _cmd, NSString *identifier, id queue, id handler) {
    return YES;   // accepted, but iDesk never wakes up for it
}

static BOOL ShimSubmitTask(id self, SEL _cmd, id request, NSError **error) {
    if (error) *error = [NSError errorWithDomain:@"BGTaskSchedulerErrorDomain" code:1   // Unavailable
                                        userInfo:@{NSLocalizedDescriptionKey: @"Background tasks are not available in iDesk."}];
    return NO;
}

// MARK: - API

void GuestShimsSetWindow(int app, UIWindow *window) { AppAt(app).window = window; }
void GuestShimsSetAppDelegate(int app, id delegate) { AppAt(app).delegate = delegate; }
void GuestShimsSetActiveApp(int app) { if (AppAt(app)) gActiveApp = app; }
void GuestShimsEndLoading(void) { gLoadingApp = -1; }

int GuestShimsBeginApp(NSBundle *bundle) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gApps = [NSMutableArray array];
        gHostBundle = NSBundle.mainBundle;
        gCopyMatching = SecItemCopyMatching;
        gAdd = SecItemAdd;
        gUpdate = SecItemUpdate;
        gDelete = SecItemDelete;
        gGetMainBundle = CFBundleGetMainBundle;
        gDlopenFrom = (DlopenFrom)dlsym(RTLD_DEFAULT, "dlopen_from");
        gBundleInitWithPath = (void *)GuestShimsReplaceMethod(NSBundle.class, @selector(initWithPath:), NO, (IMP)ShimBundleInitWithPath);
        gBundleInitWithURL = (void *)GuestShimsReplaceMethod(NSBundle.class, @selector(initWithURL:), NO, (IMP)ShimBundleInitWithURL);
        gPathForResourceInDirectory = (void *)GuestShimsReplaceMethod(NSBundle.class, @selector(pathForResource:ofType:inDirectory:), NO,
                                                                      (IMP)ShimPathForResourceInDirectory);
        gURLForResourceInDirectory = (void *)GuestShimsReplaceMethod(NSBundle.class, @selector(URLForResource:withExtension:subdirectory:), NO,
                                                                     (IMP)ShimURLForResourceInDirectory);
        GuardAttributedStrings();
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();     // the GPU's own class (AGX…Device) overrides these
        if (device) {
            gNewLibraryWithFile = (void *)GuestShimsReplaceMethod(object_getClass(device), @selector(newLibraryWithFile:error:), NO,
                                                                  (IMP)ShimNewLibraryWithFile);
            gNewLibraryWithURL = (void *)GuestShimsReplaceMethod(object_getClass(device), @selector(newLibraryWithURL:error:), NO,
                                                                 (IMP)ShimNewLibraryWithURL);
        }

        gMainBundle = (void *)GuestShimsReplaceMethod(NSBundle.class, @selector(mainBundle), YES, (IMP)ShimMainBundle);
        gLocalized = (void *)GuestShimsReplaceMethod(NSBundle.class, @selector(localizedStringForKey:value:table:), NO, (IMP)ShimLocalized);
        gLocalizedIn = (void *)GuestShimsReplaceMethod(NSBundle.class, NSSelectorFromString(@"localizedStringForKey:value:table:localization:"),
                                       NO, (IMP)ShimLocalizedIn);
        gLocalizedAmong = (void *)GuestShimsReplaceMethod(NSBundle.class, NSSelectorFromString(@"localizedStringForKey:value:table:localizations:"),
                                          NO, (IMP)ShimLocalizedAmong);
        gAttributed = (void *)GuestShimsReplaceMethod(NSBundle.class, NSSelectorFromString(@"localizedAttributedStringForKey:value:table:"),
                                      NO, (IMP)ShimAttributed);
        gAttributedIn = (void *)GuestShimsReplaceMethod(NSBundle.class,
                                        NSSelectorFromString(@"localizedAttributedStringForKey:value:table:localization:"),
                                        NO, (IMP)ShimAttributedIn);
        gContainerURL = (void *)GuestShimsReplaceMethod(NSFileManager.class, @selector(containerURLForSecurityApplicationGroupIdentifier:),
                                        NO, (IMP)ShimContainerURL);
        gAppDelegate = (void *)GuestShimsReplaceMethod(UIApplication.class, @selector(delegate), NO, (IMP)ShimAppDelegate);
        gAppKeyWindow = (void *)GuestShimsReplaceMethod(UIApplication.class, NSSelectorFromString(@"keyWindow"), NO, (IMP)ShimAppKeyWindow);
        gAppWindows = (void *)GuestShimsReplaceMethod(UIApplication.class, NSSelectorFromString(@"windows"), NO, (IMP)ShimAppWindows);
        gSceneKeyWindow = (void *)GuestShimsReplaceMethod(UIWindowScene.class, @selector(keyWindow), NO, (IMP)ShimSceneKeyWindow);

        // Called right away for every image already loaded (gActive is still NO, so they are skipped),
        // then for each guest image as dyld adds it, before its initializers run.
        _dyld_register_func_for_add_image(ImageAdded);
        gActive = YES;
    });
    GuestShimsApp *app = [GuestShimsApp new];
    app.bundle = bundle;
    NSString *suffix = [NSString stringWithFormat:@"/%@/%@", bundle.bundlePath.lastPathComponent,
                        bundle.executablePath.lastPathComponent];
    app.executableSuffix = strdup(suffix.fileSystemRepresentation);
    app.ownLibraries = OwnLibraries(bundle);
    [gApps addObject:app];
    int index = (int)gApps.count - 1;
    atomic_store(&gAppCount, index + 1);
    gLoadingApp = index;
    gActiveApp = index;
    return index;
}

void GuestShimsDidLoad(int index) {
    // Each class is hooked once, by the first app that brings its framework in.
    static BOOL cloudKit, healthKit, backgroundTasks;
    Class container = NSClassFromString(@"CKContainer");
    if (container && !cloudKit) {
        cloudKit = YES;
        GuestShimsReplaceMethod(container, NSSelectorFromString(@"defaultContainer"), YES, (IMP)ShimDefaultContainer);
        GuestShimsReplaceMethod(container, NSSelectorFromString(@"containerWithIdentifier:"), YES, (IMP)ShimContainerWithIdentifier);
    }
    Class store = NSClassFromString(@"HKHealthStore");
    if (store && !healthKit) {
        healthKit = YES;
        GuestShimsReplaceMethod(store, NSSelectorFromString(@"requestAuthorizationToShareTypes:readTypes:completion:"), NO,
                (IMP)ShimHealthAuthorization);
    }
    Class scheduler = NSClassFromString(@"BGTaskScheduler");
    if (scheduler && !backgroundTasks) {
        backgroundTasks = YES;
        GuestShimsReplaceMethod(scheduler, NSSelectorFromString(@"registerForTaskWithIdentifier:usingQueue:launchHandler:"), NO,
                (IMP)ShimRegisterTask);
        GuestShimsReplaceMethod(scheduler, NSSelectorFromString(@"submitTaskRequest:error:"), NO, (IMP)ShimSubmitTask);
    }

    // Fonts the guest ships (UIAppFonts): UIKit registered iDesk's list at launch, not this one.
    NSBundle *bundle = AppAt(index).bundle;
    for (id name in bundle.infoDictionary[@"UIAppFonts"]) {
        if (![name isKindOfClass:NSString.class]) continue;
        NSURL *url = [bundle.bundleURL URLByAppendingPathComponent:name];
        CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, NULL);
    }
}
