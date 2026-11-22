#import "CategoryRepair.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <dlfcn.h>

// `@dynamic` properties declared in a category on CALayer (or CAAnimation) have no code: Core Animation generates their
// accessors from the class's property list. But it reads that list only once, when the class is first used -
// in iDesk, long before the guest app is loaded. The result (seen with YouTube / AsyncDisplayKit):
//   -[_ASDisplayLayer asyncdisplaykit_isAsyncTransactionContainer]: unrecognized selector
//
// So after loading a guest app, find the system CALayer / CAAnimation classes the guest has categories on, and create
// accessors for the @dynamic properties the class does not answer yet. Values are stored in the layer via KVC,
// the same place Core Animation keeps them. (Regular category methods are attached by the Objective‑C runtime.)

/// objc4's category_t: only the `cls` field is needed.
typedef struct {
    const char *name;
    Class cls;
} CategoryHeader;

static uint32_t gFirstImage;
static BOOL gWatching;
static unsigned gAdded, gUnsupported;
static NSMutableString *gDetails;

static void Detail(NSString *line) {
    if (!gDetails) gDetails = [NSMutableString new];
    if (gDetails.length < 2000) [gDetails appendFormat:@"%@\n", line];
}

static NSString *CopyAttribute(objc_property_t property, const char *name) {
    char *value = property_copyAttributeValue(property, name);
    if (!value) return nil;
    NSString *string = @(value);
    free(value);
    return string;
}

/// Creates accessors for an @dynamic property the class does not answer yet.
static void AddDynamicAccessors(Class cls, objc_property_t property) {
    if (!CopyAttribute(property, "D")) return;                 // not @dynamic
    NSString *name = @(property_getName(property));
    NSString *type = CopyAttribute(property, "T");
    if (!name.length || !type.length) return;
    SEL getter = NSSelectorFromString(CopyAttribute(property, "G") ?: name);
    // class_getInstanceMethod also gives Core Animation a chance to generate it; only fill in what is still missing.
    if (class_getInstanceMethod(cls, getter)) return;
    NSString *setterName = CopyAttribute(property, "S") ?:
        [NSString stringWithFormat:@"set%@%@:", [name substringToIndex:1].uppercaseString, [name substringFromIndex:1]];
    SEL setter = CopyAttribute(property, "R") ? NULL : NSSelectorFromString(setterName);
    // Store under a private key: with the property's own name, KVC would call the accessor just added (infinite loop).
    NSString *key = [@"idesk_dynamic_" stringByAppendingString:name];

    id get, set;
    const char code = type.UTF8String[0];
    switch (code) {
        case '@': case '#': {
            get = ^id(CALayer *layer) { return [layer valueForKey:key]; };
            set = ^(CALayer *layer, id value) { [layer setValue:value forKey:key]; };
            break;
        }
        case 'f': {
            get = ^float(CALayer *layer) { return [[layer valueForKey:key] floatValue]; };
            set = ^(CALayer *layer, float value) { [layer setValue:@(value) forKey:key]; };
            break;
        }
        case 'd': {
            get = ^double(CALayer *layer) { return [[layer valueForKey:key] doubleValue]; };
            set = ^(CALayer *layer, double value) { [layer setValue:@(value) forKey:key]; };
            break;
        }
        case 'B': case 'c': case 'C': case 's': case 'S': case 'i': case 'I': case 'l': case 'L': case 'q': case 'Q': {
            // Integers of every size share one register: truncate to the type's width before storing.
            NSUInteger size = 8;
            NSGetSizeAndAlignment(type.UTF8String, &size, NULL);
            unsigned shift = (unsigned)(8 - MIN(size, (NSUInteger)8)) * 8;
            BOOL isSigned = strchr("csilq", code) != NULL;
            get = ^long long(CALayer *layer) { return [[layer valueForKey:key] longLongValue]; };
            set = ^(CALayer *layer, long long raw) {
                long long value = isSigned ? (raw << shift) >> shift
                                           : (long long)(((unsigned long long)raw << shift) >> shift);
                [layer setValue:@(value) forKey:key];
            };
            break;
        }
        default: {
            gUnsupported++;
            Detail([NSString stringWithFormat:@"%s.%@: @dynamic of type %@ not supported", class_getName(cls), name, type]);
            return;
        }
    }
    const char *t = type.UTF8String;
    class_addMethod(cls, getter, imp_implementationWithBlock(get), [NSString stringWithFormat:@"%s@:", t].UTF8String);
    if (setter) class_addMethod(cls, setter, imp_implementationWithBlock(set), [NSString stringWithFormat:@"v@:%s", t].UTF8String);
    gAdded++;
    Detail([NSString stringWithFormat:@"%s.%@: added", class_getName(cls), name]);
}

/// `done`: classes already handled for this image. Not process-wide: another guest app loaded later can declare
/// new @dynamic properties on a class an earlier app already had repaired.
static void RepairClass(Class cls, NSMutableSet<Class> *done) {
    if ([done containsObject:cls]) return;
    [done addObject:cls];
    unsigned count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    for (unsigned i = 0; i < count; i++) AddDynamicAccessors(cls, properties[i]);
    free(properties);
}

/// Whether `address` lies in one of the guest app's images (loaded from gFirstImage on).
static BOOL IsInGuestImage(const void *address) {
    Dl_info info;
    if (!dladdr(address, &info) || !info.dli_fbase) return YES;     // unknown: treat as the guest's and leave it alone
    for (uint32_t i = gFirstImage; i < _dyld_image_count(); i++) {
        if ((const void *)_dyld_get_image_header(i) == info.dli_fbase) return YES;
    }
    return NO;
}

/// Walks the categories in a guest image and repairs the target class if it is a system CALayer / CAAnimation.
static void RepairImage(const struct mach_header_64 *header) {
    NSMutableSet<Class> *done = [NSMutableSet set];
    const char *segments[] = { "__DATA_CONST", "__DATA", "__DATA_DIRTY" };
    for (size_t s = 0; s < 3; s++) {
        unsigned long size = 0;
        const CategoryHeader *const *list =
            (const CategoryHeader *const *)getsectiondata(header, segments[s], "__objc_catlist", &size);
        if (!list) continue;
        for (unsigned long i = 0; i < size / sizeof(void *); i++) {
            const CategoryHeader *cat = list[i];
            if (!cat || !cat->cls) continue;               // target class not present on this device
            // Only touch system classes: a guest Swift class here is an unresolved "stub",
            // and asking the runtime about it kills the process immediately.
            if (IsInGuestImage((__bridge const void *)cat->cls)) continue;
            if ([cat->cls isSubclassOfClass:CALayer.class] || [cat->cls isSubclassOfClass:CAAnimation.class]) RepairClass(cat->cls, done);
        }
    }
}

NSString *GuestCategoryRepairLogPath(void) {
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [library stringByAppendingPathComponent:@"iDeskCategoryRepair.txt"];
}

static void WriteLog(void) {
    NSString *log = [NSString stringWithFormat:@"@dynamic properties on CALayer/CAAnimation: %u added, %u unsupported.\n%@",
                     gAdded, gUnsupported, gDetails ?: @""];
    [log writeToFile:GuestCategoryRepairLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

/// Guest libraries loaded later (dlopen at runtime) need the repair too.
static void ImageAdded(const struct mach_header *header, intptr_t slide) {
    if (!gWatching || !header || header->magic != MH_MAGIC_64) return;
    unsigned before = gAdded + gUnsupported;
    RepairImage((const struct mach_header_64 *)header);
    if (gAdded + gUnsupported != before) WriteLog();
}

unsigned GuestRepairCategories(uint32_t firstImage) {
    gFirstImage = firstImage;
    for (uint32_t i = firstImage; i < _dyld_image_count(); i++) {
        const struct mach_header *header = _dyld_get_image_header(i);
        if (header && header->magic == MH_MAGIC_64) RepairImage((const struct mach_header_64 *)header);
    }
    WriteLog();

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // The callback runs right away for every loaded image: gWatching is still NO, so they are skipped.
        _dyld_register_func_for_add_image(ImageAdded);
    });
    gWatching = YES;
    return gAdded;
}
