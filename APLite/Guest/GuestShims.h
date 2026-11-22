#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Generic compatibility layer for guest apps (see GuestShims.m). Nothing in here is specific to one app:
/// each shim covers something that is different for every app loaded into another app's process.
///
/// Several guest apps can run at once. Each gets an id; code is attributed to an app by the image it lives in,
/// and per-app answers (main bundle, app delegate, key window) follow the code that asks.

/// Registers a guest app right before dlopen of its executable. Images dyld adds until GuestShimsEndLoading
/// belong to it; their symbol pointers are rewritten before their initializers run. Returns the app's id.
int GuestShimsBeginApp(NSBundle *bundle);
void GuestShimsEndLoading(void);

/// Call right after dlopen: hooks for system classes the guest brought in (CloudKit, BackgroundTasks,
/// HealthKit), fonts declared in the guest's Info.plist.
void GuestShimsDidLoad(int app);

void GuestShimsSetAppDelegate(int app, id _Nullable delegate);
/// The app's main window, returned to the app when it asks for the key window.
void GuestShimsSetWindow(int app, UIWindow *_Nullable window);

/// The app the user is working with: answers for code that cannot be attributed to any app
/// (system frameworks working on a guest's behalf from a run loop callback).
void GuestShimsSetActiveApp(int app);

/// The guest app whose code is on the current call stack (its executable preferred over shared frameworks),
/// or -1. `fallback`: also accept the app being loaded / the active app when the stack names none.
int GuestShimsCallerApp(BOOL fallback);

/// Replaces a method of `cls` (instance) or its metaclass (`classMethod`) and returns the old implementation, or
/// NULL if there is no such method. An inherited method is added on `cls` itself, so the superclass (and every
/// other subclass) keeps the original.
IMP _Nullable GuestShimsReplaceMethod(Class _Nullable cls, SEL selector, BOOL classMethod, IMP replacement);

/// Whether `address` lies in a guest app's code (its executable or one of its frameworks).
BOOL GuestShimsIsGuestCode(const void *address);

/// Name of the exception thrown when the guest's main() reaches UIApplicationMain.
extern NSString *const GuestShimsMainReached;

/// What the most recent guest main() passed to UIApplicationMain. Reset before running a main().
void GuestShimsResetMainCall(void);
BOOL GuestShimsMainCalled(void);
NSString *_Nullable GuestShimsMainPrincipalClass(void);
NSString *_Nullable GuestShimsMainDelegateClass(void);

NS_ASSUME_NONNULL_END
