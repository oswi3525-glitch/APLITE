#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Records where iDesk crashed (usually because of a guest app), so the user can send it on the next launch.
@interface CrashReporter : NSObject
+ (void)install;
/// Name of the running guest app, included in the report.
+ (void)setGuestName:(NSString *)name;
/// Report from the previous crash (if any); deleted once read.
+ (nullable NSString *)takeLastReport;
@end

/// The guest app called exit(): record who called it (`caller` is the return address), then the caller exits.
void CrashReporterRecordExit(int code, const void *caller);

NS_ASSUME_NONNULL_END
