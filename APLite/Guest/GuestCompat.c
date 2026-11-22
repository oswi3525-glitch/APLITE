// System functions iOS has removed but old libraries in guest apps (e.g. libsubstrate.dylib from old
// jailbreaks) still call. iDesk provides them; ImportWeakener binds the guest's imports here (flat lookup).

#include <mach/mach.h>
#include <mach/task_info.h>

/// Older dyld returned a pointer to the `dyld_all_image_infos` table. iOS still exposes that table through
/// task_info(TASK_DYLD_INFO), so the result is identical to the original function.
__attribute__((used, visibility("default")))
const void *_dyld_get_all_image_infos(void) {
    struct task_dyld_info info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return (const void *)(uintptr_t)info.all_image_info_addr;
}
