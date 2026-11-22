#import <Foundation/Foundation.h>

/// Adds accessors for @dynamic properties a guest app declares on CALayer / CAAnimation (see CategoryRepair.m).
/// `firstImage`: dyld index of the guest's first image. Returns the number of properties fixed.
unsigned GuestRepairCategories(uint32_t firstImage);

/// Log of this step (attached to crash reports).
NSString *GuestCategoryRepairLogPath(void);
