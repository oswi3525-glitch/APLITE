#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Loads other apps (unpacked from an IPA and patched by MachOPatcher) into the iDesk process, then drives each
/// app's lifecycle (delegate, scene) to get its windows. Several apps can run at the same time.
///
/// An app is identified by a handle window returned at launch (never shown). Every window the app creates, at
/// launch or later (a splash window, the real main window, overlays, HUDs), is tracked, kept off the iPhone screen
/// and shown in the app's desktop window. A hang in any guest hangs iDesk.
@interface GuestRuntime : NSObject

/// Loads and launches the app, or returns its handle if it already runs. The app may have no window yet.
/// `scene` is the scene the guest app will believe is its own.
+ (nullable UIWindow *)launchBundleAtPath:(NSString *)bundlePath
                                    scene:(UIWindowScene *)scene
                                    error:(NSError **)error;

/// The app's visible windows, bottom to top (empty until it shows one).
+ (NSArray<UIWindow *> *)windowsOfAppWithWindow:(UIWindow *)handle;

/// The app's topmost window that has something under `point` (window coordinates), else its main window.
+ (UIWindow *)touchWindowAt:(CGPoint)point appWindow:(UIWindow *)handle;

/// Whether the app wants landscape: it asked to rotate (a video player going fullscreen) or shows a screen that
/// only supports landscape. iDesk's scene never rotates for a guest; its desktop window fills the display instead.
+ (BOOL)appWantsLandscapeWithWindow:(UIWindow *)handle;

/// Back for any app, like swiping from the left edge on the iPhone: the visible navigation stack goes back one screen,
/// or a screen shown over the app is closed. NO if there is nothing to go back from.
+ (BOOL)goBackInAppWithWindow:(UIWindow *)handle;

/// The user is working with this app: code that cannot be attributed to an app is attributed to it.
+ (void)activateAppWithWindow:(UIWindow *)handle;

/// Its desktop window was closed / opened again. Code cannot be unloaded from a process, so a closed app keeps
/// existing until iDesk quits; it gets the events of going to the background (most apps stop playing and pause
/// their work), and those of coming back when reopened.
+ (void)suspendAppWithWindow:(UIWindow *)handle;
+ (void)resumeAppWithWindow:(UIWindow *)handle;

/// Forwards scene lifecycle events (background, foreground…) to every guest app.
+ (void)forwardSceneEvent:(SEL)selector scene:(UIScene *)scene;

@end

/// Posted when a guest opens an in-app browser (SFSafariViewController); the object is the NSURL to open.
extern NSNotificationName const GuestRuntimeOpenURLNotification;
/// A guest app asked to rotate (the desktop window updates its layout at once).
extern NSNotificationName const GuestRuntimeWindowsChangedNotification;
/// A guest app's local notification is due. userInfo: bundlePath, title, subtitle, body (strings).
extern NSNotificationName const GuestRuntimeNotificationNotification;

/// Synthetic touches into a guest app's window (the external display takes no real touches).
@interface GuestTouch : NSObject

/// Coordinates are in the guest window.
+ (void)beginAt:(CGPoint)point inWindow:(UIWindow *)window;
+ (void)moveTo:(CGPoint)point;
+ (void)end;
+ (void)cancel;
@property (class, nonatomic, readonly) BOOL isActive;

/// Scrolls the scroll view under `point`. Returns NO if there is nothing to scroll.
+ (BOOL)scrollAt:(CGPoint)point inWindow:(UIWindow *)window dx:(CGFloat)dx dy:(CGFloat)dy;

/// Types text / deletes / presses Enter in the guest app's current text input.
+ (BOOL)insertText:(NSString *)text inWindow:(UIWindow *)window;
+ (BOOL)deleteBackwardInWindow:(UIWindow *)window;
/// Sends an edit action (copy:, cut:, paste:, selectAll:) to the guest's current text input or selection.
+ (BOOL)performEditAction:(SEL)action inWindow:(UIWindow *)window;

@end

NS_ASSUME_NONNULL_END
