#import "CrashReporter.h"
#import "CategoryRepair.h"
#import "MachOImage.h"
#import <UIKit/UIKit.h>
#import <signal.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>
#import <string.h>
#import <pthread.h>
#import <sys/ucontext.h>
#import <mach/mach.h>
#import <os/proc.h>
#import <sys/sysctl.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <stdatomic.h>
#import <errno.h>

// Records why iDesk quit (usually a guest app sharing the process), so the user can send it on the next launch.
//
// Three layers, because guest apps often install their own crash handlers (Crashlytics…) over iDesk's:
// 1. Signals (SIGSEGV, SIGABRT…) and Objective‑C exceptions. Re-claimed periodically if overridden, and after
//    recording they are forwarded to the guest's handler so it keeps working.
// 2. A Mach exception port: catches EXC_BAD_ACCESS… even when signals are blocked elsewhere.
// 3. A "running" heartbeat every 2 seconds (guest app, memory). A SIGKILL from iOS (out of memory, code signing…)
//    cannot be caught; finding the heartbeat on the next launch shows iDesk was killed.
//    It also watches the main thread: when an app blocks it (everything on the display freezes), the heartbeat
//    records for how long and where the main thread is stuck, so a frozen iDesk that was then closed (by iOS's
//    watchdog or by the user) is reported as a freeze in that code, not as running out of memory.

static char gReportPath[1024];
/// The UUID of iDesk's executable: a heartbeat left by another build means iDesk was updated or reinstalled (which
/// kills the running copy), not that it crashed.
static char gBuildID[40];

static void ReadBuildID(void) {
    const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(0);
    if (!header || header->magic != MH_MAGIC_64) return;
    const uint8_t *cmd = (const uint8_t *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cmd;
        if (lc->cmd == LC_UUID) {
            const uint8_t *u = ((const struct uuid_command *)lc)->uuid;
            for (int k = 0; k < 16; k++) snprintf(gBuildID + 2 * k, 3, "%02x", u[k]);
            return;
        }
        cmd += lc->cmdsize;
    }
}
static char gHeartbeatPath[1024];
static char gGuestName[256];
static volatile sig_atomic_t gReported = 0;
static volatile sig_atomic_t gInForeground = 1;
static volatile sig_atomic_t gMemoryWarnings = 0;
static NSUncaughtExceptionHandler *gChainedExceptionHandler;
static const int kSignals[] = { SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE, SIGSYS };
#define kSignalCount (sizeof kSignals / sizeof kSignals[0])
static struct sigaction gChained[kSignalCount];
static mach_port_t gExceptionPort = MACH_PORT_NULL;

static void SignalHandler(int sig, siginfo_t *info, void *context);
static void ExceptionHandler(NSException *exception);

// MARK: - Writing the report

static void WriteString(int fd, const char *s) { if (s) write(fd, s, strlen(s)); }

// Images known so far, recorded as dyld adds them. A crash can happen inside dyld while it holds its lock (loading
// a library); asking dyld then (dladdr) would wait for that lock forever and freeze iDesk instead of reporting.
typedef struct { uintptr_t start, end; const char *name; } KnownImage;
static KnownImage gKnownImages[4096];
static _Atomic uint32_t gKnownImageCount;

static void RecordImage(const struct mach_header *header, intptr_t slide) {
    if (!header || header->magic != MH_MAGIC_64) return;
    uint32_t index = atomic_load(&gKnownImageCount);
    if (index >= sizeof(gKnownImages) / sizeof(gKnownImages[0])) return;
    KnownImage image = { 0, 0, "?" };
    MachOTextRange(header, slide, &image.start, &image.end);
    Dl_info info;
    if (dladdr(header, &info) && info.dli_fname) image.name = info.dli_fname;   // stays valid while loaded
    gKnownImages[index] = image;
    atomic_store(&gKnownImageCount, index + 1);
}

static void WriteAddress(int fd, const char *label, uintptr_t address) {
    char line[700];
    const KnownImage *found = NULL;
    uint32_t count = atomic_load(&gKnownImageCount);
    for (uint32_t i = 0; address && i < count; i++) {
        if (address >= gKnownImages[i].start && address < gKnownImages[i].end) { found = &gKnownImages[i]; break; }
    }
    if (found) {
        const char *image = strrchr(found->name, '/');
        image = image ? image + 1 : found->name;
        snprintf(line, sizeof line, "%s 0x%lx %s + 0x%lx\n", label, (unsigned long)address, image,
                 (unsigned long)(address - found->start));
    } else {
        snprintf(line, sizeof line, "%s 0x%lx ?\n", label, (unsigned long)address);
    }
    WriteString(fd, line);
}

/// Walks the frame-pointer chain: [fp] = previous fp, [fp + 8] = return address.
static void WriteStack(int fd, uintptr_t fp) {
    for (int i = 0; i < 40 && fp && (fp & 0xF) == 0; i++) {
        uintptr_t next = ((uintptr_t *)fp)[0];
        uintptr_t ret = ((uintptr_t *)fp)[1] & 0x0000000FFFFFFFFFULL;   // strip PAC bits
        if (!ret) break;
        char label[16];
        snprintf(label, sizeof label, "#%02d", i);
        WriteAddress(fd, label, ret);
        if (next <= fp) break;
        fp = next;
    }
}

// MARK: - The last lines printed

// Apps often print why they stop just before calling abort() (a failed check, an assertion). stderr goes through a
// pipe: everything still reaches the real stderr, and the last few KB stay in a ring buffer for the report.
static char gOutput[4096];
static _Atomic uint64_t gOutputTotal;           // bytes ever written into gOutput
static int gRealStderr = -1;
static int gOutputPipe = -1;                    // read end

static void KeepOutput(const char *bytes, ssize_t n) {
    if (gRealStderr >= 0) write(gRealStderr, bytes, (size_t)n);
    uint64_t total = atomic_load(&gOutputTotal);
    for (ssize_t i = 0; i < n; i++) gOutput[(total + (uint64_t)i) % sizeof gOutput] = bytes[i];
    atomic_store(&gOutputTotal, total + (uint64_t)n);
}

static void *OutputThread(void *arg) {
    char buffer[1024];
    ssize_t n;
    while ((n = read(gOutputPipe, buffer, sizeof buffer)) > 0 || (n < 0 && errno == EAGAIN)) {
        if (n > 0) KeepOutput(buffer, n);
        else usleep(20000);          // the crash handler made the pipe non-blocking
    }
    return NULL;
}

static void CaptureOutput(void) {
    int fds[2];
    if (pipe(fds) != 0) return;
    gRealStderr = dup(STDERR_FILENO);
    if (gRealStderr < 0 || dup2(fds[1], STDERR_FILENO) < 0) { close(fds[0]); close(fds[1]); return; }
    close(fds[1]);
    gOutputPipe = fds[0];
    pthread_t thread;
    if (pthread_create(&thread, NULL, OutputThread, NULL) == 0) pthread_detach(thread);
}

/// Called while crashing: only write().
static void WriteOutput(int fd) {
    // What was printed right before the crash (the reason, typically) may still be in the pipe: give the reader a
    // moment, then take what is left without waiting.
    if (gOutputPipe >= 0) {
        struct timespec pause = { 0, 30 * 1000 * 1000 };
        nanosleep(&pause, NULL);
        fcntl(gOutputPipe, F_SETFL, fcntl(gOutputPipe, F_GETFL) | O_NONBLOCK);
        char buffer[1024];
        ssize_t n;
        while ((n = read(gOutputPipe, buffer, sizeof buffer)) > 0) KeepOutput(buffer, n);
    }
    uint64_t total = atomic_load(&gOutputTotal);
    if (!total) return;
    WriteString(fd, "Last output:\n");
    size_t size = sizeof gOutput;
    if (total <= size) {
        write(fd, gOutput, (size_t)total);
    } else {
        size_t start = (size_t)(total % size);
        write(fd, gOutput + start, size - start);
        write(fd, gOutput, start);
    }
    WriteString(fd, "\n");
}

static void WriteMemory(int fd) {
    task_vm_info_data_t vm;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    char line[200];
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &count) == KERN_SUCCESS) {
        snprintf(line, sizeof line, "RAM in use: %llu MB, available: %zu MB, memory warnings: %d\n",
                 vm.phys_footprint / (1024 * 1024), os_proc_available_memory() / (1024 * 1024), (int)gMemoryWarnings);
        WriteString(fd, line);
    }
}

static int OpenReport(void) {
    if (gReported) return -1;   // record only the first one, so cascading faults do not overwrite it
    gReported = 1;
    return open(gReportPath, O_WRONLY | O_CREAT | O_TRUNC, 0600);
}

// MARK: - 1. Signals

static void SignalHandler(int sig, siginfo_t *info, void *context) {
    int fd = OpenReport();
    if (fd >= 0) {
        char line[512];
        snprintf(line, sizeof line, "Signal %d (%s), fault address 0x%lx, guest app: %s\n",
                 sig, strsignal(sig), (unsigned long)info->si_addr, gGuestName[0] ? gGuestName : "(none)");
        WriteString(fd, line);
        WriteMemory(fd);
#if defined(__arm64__)
        ucontext_t *uc = (ucontext_t *)context;
        if (uc && uc->uc_mcontext) {
            WriteAddress(fd, "pc", (uintptr_t)__darwin_arm_thread_state64_get_pc(uc->uc_mcontext->__ss));
            WriteAddress(fd, "lr", (uintptr_t)__darwin_arm_thread_state64_get_lr(uc->uc_mcontext->__ss));
            WriteStack(fd, (uintptr_t)__darwin_arm_thread_state64_get_fp(uc->uc_mcontext->__ss));
        }
#endif
        WriteOutput(fd);
        close(fd);
        unlink(gHeartbeatPath);
    }
    // Forward to the guest's crash handler (if any), then let the system handle it as usual.
    for (size_t i = 0; i < kSignalCount; i++) {
        if (kSignals[i] != sig) continue;
        struct sigaction prev = gChained[i];
        if ((prev.sa_flags & SA_SIGINFO) && prev.sa_sigaction && prev.sa_sigaction != SignalHandler) {
            prev.sa_sigaction(sig, info, context);
        } else if (!(prev.sa_flags & SA_SIGINFO) && prev.sa_handler != SIG_DFL && prev.sa_handler != SIG_IGN) {
            prev.sa_handler(sig);
        }
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void ExceptionHandler(NSException *exception) {
    int fd = OpenReport();
    if (fd >= 0) {
        NSMutableString *text = [NSMutableString stringWithFormat:@"Exception %@: %@\nguest app: %s\n",
                                 exception.name, exception.reason, gGuestName[0] ? gGuestName : "(none)"];
        for (NSString *frame in exception.callStackSymbols) [text appendFormat:@"%@\n", frame];
        WriteString(fd, text.UTF8String);
        WriteMemory(fd);
        close(fd);
        unlink(gHeartbeatPath);
    }
    if (gChainedExceptionHandler && gChainedExceptionHandler != ExceptionHandler) gChainedExceptionHandler(exception);
}

void CrashReporterRecordExit(int code, const void *caller) {
    int fd = OpenReport();
    if (fd < 0) return;
    char line[600];
    snprintf(line, sizeof line, "The guest app called exit(%d), so APLite quit with it. Guest app: %s\n"
             "Usually the app checked its environment (jailbreak, signature, running inside another app) and shut itself down.\n",
             code, gGuestName[0] ? gGuestName : "(none)");
    WriteString(fd, line);
    WriteAddress(fd, "called from", (uintptr_t)caller & 0x0000000FFFFFFFFFULL);
    WriteStack(fd, (uintptr_t)__builtin_frame_address(0));
    WriteMemory(fd);
    close(fd);
    unlink(gHeartbeatPath);
}

/// Re-installs iDesk's handlers if a guest app replaced them; keeps the guest's to forward to.
static void Reassert(void) {
    struct sigaction ours = {0};
    ours.sa_sigaction = SignalHandler;
    ours.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&ours.sa_mask);
    for (size_t i = 0; i < kSignalCount; i++) {
        struct sigaction current;
        if (sigaction(kSignals[i], NULL, &current) != 0) continue;
        BOOL isOurs = (current.sa_flags & SA_SIGINFO) && current.sa_sigaction == SignalHandler;
        if (!isOurs) {
            gChained[i] = current;
            sigaction(kSignals[i], &ours, NULL);
        }
    }
    NSUncaughtExceptionHandler *current = NSGetUncaughtExceptionHandler();
    if (current != ExceptionHandler) {
        gChainedExceptionHandler = current;
        NSSetUncaughtExceptionHandler(ExceptionHandler);
    }
}

// MARK: - 2. Mach exceptions

typedef struct {
    mach_msg_header_t head;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t thread;
    mach_msg_port_descriptor_t task;
    NDR_record_t ndr;
    exception_type_t exception;
    mach_msg_type_number_t codeCount;
    int64_t code[2];
    char trailer[512];
} ExceptionRequest;

typedef struct {
    mach_msg_header_t head;
    NDR_record_t ndr;
    kern_return_t result;
} ExceptionReply;

static void *ExceptionThread(void *unused) {
    pthread_setname_np("iDesk.crash");
    for (;;) {
        ExceptionRequest request = {0};
        if (mach_msg(&request.head, MACH_RCV_MSG, 0, sizeof request, gExceptionPort,
                     MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL) != KERN_SUCCESS) continue;

        int fd = OpenReport();
        if (fd >= 0) {
            char line[512];
            snprintf(line, sizeof line, "Mach exception %d, code 0x%llx / 0x%llx, guest app: %s\n",
                     request.exception, (unsigned long long)request.code[0], (unsigned long long)request.code[1],
                     gGuestName[0] ? gGuestName : "(none)");
            WriteString(fd, line);
            WriteMemory(fd);
#if defined(__arm64__)
            arm_thread_state64_t state;
            mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
            if (thread_get_state(request.thread.name, ARM_THREAD_STATE64, (thread_state_t)&state, &count) == KERN_SUCCESS) {
                WriteAddress(fd, "pc", (uintptr_t)__darwin_arm_thread_state64_get_pc(state));
                WriteAddress(fd, "lr", (uintptr_t)__darwin_arm_thread_state64_get_lr(state));
                WriteStack(fd, (uintptr_t)__darwin_arm_thread_state64_get_fp(state));
            }
#endif
            close(fd);
            unlink(gHeartbeatPath);
        }
        // Return failure so the system carries on as usual (turn it into a signal, write the iOS crash log).
        ExceptionReply reply = {0};
        reply.head.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(request.head.msgh_bits), 0);
        reply.head.msgh_remote_port = request.head.msgh_remote_port;
        reply.head.msgh_size = sizeof reply;
        reply.head.msgh_id = request.head.msgh_id + 100;
        reply.ndr = NDR_record;
        reply.result = KERN_FAILURE;
        mach_msg(&reply.head, MACH_SEND_MSG, sizeof reply, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    }
    return NULL;
}

static const exception_mask_t kExceptionMask = EXC_MASK_BAD_ACCESS | EXC_MASK_BAD_INSTRUCTION |
                                               EXC_MASK_ARITHMETIC | EXC_MASK_BREAKPOINT | EXC_MASK_GUARD;

static void ClaimExceptionPort(void) {
    if (gExceptionPort == MACH_PORT_NULL) return;
    task_set_exception_ports(mach_task_self(), kExceptionMask, gExceptionPort,
                             (exception_behavior_t)(EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES), THREAD_STATE_NONE);
}

static void InstallMachHandler(void) {
    // A debugger (Xcode) is attached: let it catch the exception.
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    struct kinfo_proc proc;
    size_t size = sizeof proc;
    if (sysctl(mib, 4, &proc, &size, NULL, 0) == 0 && (proc.kp_proc.p_flag & P_TRACED)) return;

    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &gExceptionPort) != KERN_SUCCESS) return;
    mach_port_insert_right(mach_task_self(), gExceptionPort, gExceptionPort, MACH_MSG_TYPE_MAKE_SEND);
    ClaimExceptionPort();
    pthread_t thread;
    pthread_create(&thread, NULL, ExceptionThread, NULL);
    pthread_detach(thread);
}

// MARK: - 3. Running heartbeat and main thread watchdog

static mach_port_t gMainThread = MACH_PORT_NULL;
static uintptr_t gMainStackTop, gMainStackBottom;    // the main thread's stack: [bottom, top)
static _Atomic uint64_t gMainLastSeen;               // mach_absolute_time() when the main thread last answered
static _Atomic int gMainPingPending;
static const double kStallSeconds = 3;

static double SecondsSince(uint64_t then) {
    static mach_timebase_info_data_t timebase;
    if (!timebase.denom) mach_timebase_info(&timebase);
    uint64_t now = mach_absolute_time();
    return now > then ? (double)(now - then) * timebase.numer / timebase.denom / 1e9 : 0;
}

/// Asks the main thread to answer; called every second from the timer's queue.
static void PingMainThread(void) {
    if (atomic_exchange(&gMainPingPending, 1)) return;          // the last ping is still waiting: it is blocked
    dispatch_async(dispatch_get_main_queue(), ^{
        atomic_store(&gMainLastSeen, mach_absolute_time());
        atomic_store(&gMainPingPending, 0);
    });
}

/// Where the blocked main thread is. While it is suspended only its stack is read (addresses within its own stack,
/// so a broken frame chain cannot crash iDesk) and nothing that could take a lock it holds; formatting comes after.
static void WriteMainThreadStack(int fd) {
#if defined(__arm64__)
    if (gMainThread == MACH_PORT_NULL || pthread_main_np() || thread_suspend(gMainThread) != KERN_SUCCESS) return;
    uintptr_t frames[42];
    int count = 0;
    arm_thread_state64_t state;
    mach_msg_type_number_t n = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(gMainThread, ARM_THREAD_STATE64, (thread_state_t)&state, &n) == KERN_SUCCESS) {
        frames[count++] = (uintptr_t)__darwin_arm_thread_state64_get_pc(state) & 0x0000000FFFFFFFFFULL;
        frames[count++] = (uintptr_t)__darwin_arm_thread_state64_get_lr(state) & 0x0000000FFFFFFFFFULL;
        uintptr_t sp = (uintptr_t)__darwin_arm_thread_state64_get_sp(state);
        uintptr_t fp = (uintptr_t)__darwin_arm_thread_state64_get_fp(state);
        uintptr_t low = sp > gMainStackBottom ? sp : gMainStackBottom;
        while (count < 42 && fp >= low && fp + 16 <= gMainStackTop && (fp & 0xF) == 0) {
            uintptr_t next = ((uintptr_t *)fp)[0];
            uintptr_t ret = ((uintptr_t *)fp)[1] & 0x0000000FFFFFFFFFULL;
            if (!ret) break;
            frames[count++] = ret;
            if (next <= fp) break;
            fp = next;
        }
    }
    thread_resume(gMainThread);
    for (int i = 0; i < count; i++) {
        char label[16];
        if (i == 0) strlcpy(label, "pc", sizeof label);
        else if (i == 1) strlcpy(label, "lr", sizeof label);
        else snprintf(label, sizeof label, "#%02d", i - 2);
        WriteAddress(fd, label, frames[i]);
    }
#endif
}

static void WriteHeartbeat(void) {
    if (!gGuestName[0]) return;                 // no guest app running yet: nothing to record
    int fd = open(gHeartbeatPath, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return;
    char line[600];
    snprintf(line, sizeof line, "guest app: %s\nstate: %s\nbuild: %s\n", gGuestName,
             gInForeground ? "foreground" : "background", gBuildID);
    WriteString(fd, line);
    WriteMemory(fd);
    double stalled = atomic_load(&gMainPingPending) ? SecondsSince(atomic_load(&gMainLastSeen)) : 0;
    // Only from the watchdog's thread: called on the main thread itself (setGuestName after a slow launch), it would
    // suspend the main thread from the main thread and never come back (iDesk froze for good).
    if (gInForeground && stalled >= kStallSeconds && !pthread_main_np()) {
        snprintf(line, sizeof line, "main thread: not responding for %.0f s, stuck in:\n", stalled);
        WriteString(fd, line);
        WriteMainThreadStack(fd);
    }
    close(fd);
}

@implementation CrashReporter

+ (void)install {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    strlcpy(gReportPath, [dir stringByAppendingPathComponent:@"iDeskLastCrash.txt"].fileSystemRepresentation, sizeof gReportPath);
    strlcpy(gHeartbeatPath, [dir stringByAppendingPathComponent:@"iDeskRunning.txt"].fileSystemRepresentation, sizeof gHeartbeatPath);
    ReadBuildID();
    _dyld_register_func_for_add_image(RecordImage);   // every loaded image now, then each new one
    pthread_t main = pthread_self();                   // install runs on the main thread (didFinishLaunching)
    gMainThread = pthread_mach_thread_np(main);
    gMainStackTop = (uintptr_t)pthread_get_stackaddr_np(main);
    gMainStackBottom = gMainStackTop - pthread_get_stacksize_np(main);
    atomic_store(&gMainLastSeen, mach_absolute_time());
    CaptureOutput();

    // Separate stack: stack-overflow crashes can still be recorded.
    static char altStack[64 * 1024];
    stack_t ss = { .ss_sp = altStack, .ss_size = sizeof altStack, .ss_flags = 0 };
    sigaltstack(&ss, NULL);
    Reassert();
    InstallMachHandler();

    // Every second re-claim the handlers (a guest may override them at launch), every 2 seconds write the heartbeat.
    static dispatch_source_t timer;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 4);
    static int tick = 0;
    dispatch_source_set_event_handler(timer, ^{
        Reassert();
        ClaimExceptionPort();
        PingMainThread();
        if (++tick % 2 == 0) WriteHeartbeat();
    });
    dispatch_resume(timer);

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        gInForeground = 0; WriteHeartbeat();
    }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        gInForeground = 1; WriteHeartbeat();
    }];
    [nc addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        // iDesk's own warning to a closed app (GuestRuntime) is not iOS running out of memory.
        if (n.userInfo[@"iDeskReleaseMemory"]) return;
        gMemoryWarnings++; WriteHeartbeat();
    }];
    [nc addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        unlink(gHeartbeatPath);
    }];
}

+ (void)setGuestName:(NSString *)name {
    strlcpy(gGuestName, name.UTF8String ?: "", sizeof gGuestName);
    WriteHeartbeat();
}

/// Adds function names to the frames of system libraries and of iDesk itself: "libobjc.A.dylib + 0x253c0" becomes
/// "libobjc.A.dylib + 0x253c0 (objc_getClass + 92)". Done now, not while crashing (asking dyld then can freeze):
/// those libraries are loaded again, at another address, so the offset is added to where they are now.
/// Guest apps' libraries are not loaded yet at this point (and usually stripped), so they keep the offset only.
static NSString *Symbolicate(NSString *report) {
    NSMutableDictionary<NSString *, NSNumber *> *bases = [NSMutableDictionary dictionary];
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header *header = _dyld_get_image_header(i);
        BOOL system = (header->flags & 0x80000000) != 0;          // MH_DYLIB_IN_CACHE
        if (!system && i != 0) continue;
        NSString *name = @(_dyld_get_image_name(i)).lastPathComponent;
        if (name.length && !bases[name]) bases[name] = @((uintptr_t)header);
    }
    NSRegularExpression *frame = [NSRegularExpression
        regularExpressionWithPattern:@"^(\\S+ 0x[0-9a-f]+ )(\\S+) \\+ 0x([0-9a-f]+)$" options:0 error:nil];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [report componentsSeparatedByString:@"\n"]) {
        NSTextCheckingResult *m = [frame firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        NSNumber *base = m ? bases[[line substringWithRange:[m rangeAtIndex:2]]] : nil;
        if (!base) { [lines addObject:line]; continue; }
        unsigned long long offset = strtoull([line substringWithRange:[m rangeAtIndex:3]].UTF8String, NULL, 16);
        Dl_info info;
        if (dladdr((const void *)(base.unsignedLongValue + offset), &info) && info.dli_sname) {
            uintptr_t into = base.unsignedLongValue + offset - (uintptr_t)info.dli_saddr;
            [lines addObject:[line stringByAppendingFormat:@" (%s + %lu)", info.dli_sname, (unsigned long)into]];
        } else {
            [lines addObject:line];
        }
    }
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSString *)takeLastReport {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *report = [NSString stringWithContentsOfFile:@(gReportPath) encoding:NSUTF8StringEncoding error:nil];
    NSString *heartbeat = [NSString stringWithContentsOfFile:@(gHeartbeatPath) encoding:NSUTF8StringEncoding error:nil];
    [fm removeItemAtPath:@(gReportPath) error:nil];
    [fm removeItemAtPath:@(gHeartbeatPath) error:nil];
    // The @dynamic repair log of that guest run (helps diagnose "unrecognized selector" errors).
    NSString *repair = [NSString stringWithContentsOfFile:GuestCategoryRepairLogPath() encoding:NSUTF8StringEncoding error:nil];
    if (report.length) report = Symbolicate(report);
    if (report.length && repair.length) report = [report stringByAppendingFormat:@"\n%@", repair];
    if (report.length) return report;
    // Installing a new build of iDesk (Xcode, a signer) kills the running one: not a crash.
    if (heartbeat.length && gBuildID[0] && ![heartbeat containsString:[NSString stringWithFormat:@"build: %s", gBuildID]]) {
        return nil;
    }
    // No report, the heartbeat is still there and the main thread was blocked: iDesk froze, then iOS's watchdog or
    // the user closed it.
    if (heartbeat.length && [heartbeat containsString:@"state: foreground"] &&
        [heartbeat containsString:@"main thread: not responding"]) {
        return Symbolicate([@"APLite stopped responding: the main thread was blocked (frames below), then iOS or the "
                             "user closed APLite (SIGKILL). The image named in the first frames is usually the app "
                             "that froze it.\nLast recorded state (every 2 seconds):\n" stringByAppendingString:heartbeat]);
    }
    // No report but the heartbeat is still there and iDesk was running: iOS killed the process (SIGKILL).
    if (heartbeat.length && [heartbeat containsString:@"state: foreground"]) {
        return [@"No crash was caught: iOS killed APLite (SIGKILL) while a guest app was running. "
                 "Usually out of memory, or a tweak trying to modify code, which iOS does not allow.\n"
                 "Last recorded state (every 2 seconds):\n" stringByAppendingString:heartbeat];
    }
    return nil;
}

@end
