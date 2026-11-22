#import <mach-o/loader.h>
#import <stdint.h>
#import <string.h>

/// Where a loaded image's code (__TEXT) lies, given dyld's slide. Used to tell which image an address belongs
/// to without asking dyld (dladdr takes dyld's lock, which a crash handler or a dyld callback must not wait for).
static inline void MachOTextRange(const struct mach_header *header, intptr_t slide, uintptr_t *start, uintptr_t *end) {
    *start = *end = (uintptr_t)header;
    const uint8_t *p = (const uint8_t *)((const struct mach_header_64 *)header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct segment_command_64 *segment = (const struct segment_command_64 *)p;
        if (segment->cmd == LC_SEGMENT_64 && !strcmp(segment->segname, SEG_TEXT)) {
            *start = (uintptr_t)slide + segment->vmaddr;
            *end = *start + segment->vmsize;
            return;
        }
        p += segment->cmdsize;
    }
}
