// SPDX-License-Identifier: GPL-2.0-only
/*
 * SixLinux board bring-up validation suite.
 *
 * 在目标发行版内部运行，按子命令逐项检查 CPU、SMP、内存、中断、RTC、
 * 块设备、网络和 systemd 是否按预期工作。
 */

#define _GNU_SOURCE

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/futex.h>
#include <linux/rtc.h>
#include <netdb.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

#if defined(__aarch64__)
#include <arm_neon.h>
#include <asm/hwcap.h>
#include <sys/auxv.h>
#endif

#define MEM_BLOCK (1024 * 1024)
#define IO_BLOCKS 32
#define TCP_BYTES (16 * MEM_BLOCK)

static const char *g_test = "unknown";
static int g_pass;
static int g_fail;

static void check(const char *item, bool ok, const char *fmt, ...)
{
    char detail[256];
    va_list ap;

    va_start(ap, fmt);
    vsnprintf(detail, sizeof(detail), fmt, ap);
    va_end(ap);

    if (ok)
        g_pass++;
    else
        g_fail++;
    printf("CHECK %s/%s %s %s\n", g_test, item, ok ? "PASS" : "FAIL",
           detail);
    fflush(stdout);
}

static void info(const char *item, const char *fmt, ...)
{
    char detail[256];
    va_list ap;

    va_start(ap, fmt);
    vsnprintf(detail, sizeof(detail), fmt, ap);
    va_end(ap);

    printf("INFO %s/%s %s\n", g_test, item, detail);
    fflush(stdout);
}

static long long now_ns(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static int read_first_line(const char *path, char *buf, size_t len)
{
    FILE *f = fopen(path, "r");

    if (!f)
        return -1;
    if (!fgets(buf, (int)len, f)) {
        fclose(f);
        return -1;
    }
    fclose(f);
    buf[strcspn(buf, "\n")] = '\0';
    return 0;
}

static long cpu_count(void)
{
    return sysconf(_SC_NPROCESSORS_ONLN);
}

/* ------------------------------------------------------------------ */
/* cpu                                                                */
/* ------------------------------------------------------------------ */

static int test_cpu(void)
{
#if defined(__aarch64__)
    unsigned long midr = 0;
    unsigned long ctr = 0;
    unsigned long hwcap;
    long pagesize = sysconf(_SC_PAGESIZE);
    unsigned int cacheline;
    struct utsname uts;

    asm volatile("mrs %0, midr_el1" : "=r"(midr));
    asm volatile("mrs %0, ctr_el0" : "=r"(ctr));
    cacheline = 4u << ((ctr >> 16) & 0xfu);
    hwcap = getauxval(AT_HWCAP);
    uname(&uts);

    check("arch", strcmp(uts.machine, "aarch64") == 0, "machine=%s",
          uts.machine);
    check("midr", ((midr >> 24) & 0xff) == 0x41,
          "MIDR=0x%08lx implementer=0x%02lx part=0x%03lx", midr,
          (midr >> 24) & 0xff, (midr >> 4) & 0xfff);
    check("pagesize", pagesize == 4096, "pagesize=%ld", pagesize);
    check("cacheline", cacheline >= 16 && cacheline <= 256, "cacheline=%u",
          cacheline);
    check("neon", !!(hwcap & HWCAP_ASIMD), "HWCAP_ASIMD=%d",
          !!(hwcap & HWCAP_ASIMD));
    check("crc32", !!(hwcap & HWCAP_CRC32), "HWCAP_CRC32=%d",
          !!(hwcap & HWCAP_CRC32));
    info("lse", "HWCAP_ATOMICS=%d (Cortex-A53 为 ARMv8.0，无 LSE 属正常)",
         !!(hwcap & HWCAP_ATOMICS));

    if (hwcap & HWCAP_ASIMD) {
        float32x4_t a = vdupq_n_f32(1.5f);
        float32x4_t b = vdupq_n_f32(2.5f);
        float out[4];

        vst1q_f32(out, vaddq_f32(a, b));
        check("neon-add", out[0] == 4.0f && out[3] == 4.0f,
              "1.5+2.5=[%.1f %.1f %.1f %.1f]", out[0], out[1], out[2],
              out[3]);
    }

    if (hwcap & HWCAP_CRC32) {
#if defined(__ARM_FEATURE_CRC32)
        const char *data = "123456789";
        uint32_t crc = 0xffffffffu;
        size_t i;

        for (i = 0; i < strlen(data); i++) {
            uint32_t byte = (uint32_t)data[i];

            asm volatile("crc32cb %w0, %w0, %w1" : "+r"(crc) : "r"(byte));
        }
        crc = ~crc;
        check("crc32c", crc == 0xe3069283u, "crc32c(123456789)=0x%08x",
              crc);
#else
        check("crc32c", false,
              "compiled without CRC32 instruction support");
#endif
    }

    return 0;
#else
    check("arch", false, "compiled for non-AArch64");
    return 0;
#endif
}

/* ------------------------------------------------------------------ */
/* smp                                                                */
/* ------------------------------------------------------------------ */

#define SMP_THREADS 4
#define SMP_LOOPS 1000000

static atomic_long smp_counter;

static void *smp_worker(void *arg)
{
    int i;

    (void)arg;
    for (i = 0; i < SMP_LOOPS; i++)
        atomic_fetch_add(&smp_counter, 1);
    return NULL;
}

static int futex_word;
static volatile int futex_ready;

static void *futex_worker(void *arg)
{
    (void)arg;
    __atomic_store_n(&futex_ready, 1, __ATOMIC_RELEASE);
    while (__atomic_load_n(&futex_word, __ATOMIC_ACQUIRE) == 0)
        syscall(SYS_futex, &futex_word, FUTEX_WAIT, 0, NULL, NULL, 0);
    return NULL;
}

static int test_smp(void)
{
    pthread_t threads[SMP_THREADS];
    long ncpu = cpu_count();
    FILE *cpuinfo;
    int cpuinfo_cpus = 0;
    char line[256];
    int i;
    cpu_set_t set;

    check("nproc", ncpu >= 2, "nproc=%ld", ncpu);

    cpuinfo = fopen("/proc/cpuinfo", "r");
    if (cpuinfo) {
        while (fgets(line, sizeof(line), cpuinfo)) {
            if (strncmp(line, "processor", 9) == 0)
                cpuinfo_cpus++;
        }
        fclose(cpuinfo);
    }
    check("cpuinfo", cpuinfo_cpus == ncpu, "cpuinfo-processors=%d",
          cpuinfo_cpus);

    atomic_store(&smp_counter, 0);
    for (i = 0; i < SMP_THREADS; i++)
        pthread_create(&threads[i], NULL, smp_worker, NULL);
    for (i = 0; i < SMP_THREADS; i++)
        pthread_join(threads[i], NULL);
    check("atomic", atomic_load(&smp_counter) == (long)SMP_THREADS * SMP_LOOPS,
          "atomic-total=%ld", (long)atomic_load(&smp_counter));

    CPU_ZERO(&set);
    CPU_SET(1 % (ncpu > 1 ? ncpu : 1), &set);
    if (sched_setaffinity(0, sizeof(set), &set) == 0) {
        int cpu = sched_getcpu();

        check("affinity", cpu == 1 % (ncpu > 1 ? ncpu : 1),
              "sched_getcpu=%d", cpu);
    } else {
        check("affinity", false, "sched_setaffinity failed: %s",
              strerror(errno));
    }

    {
        pthread_t waiter;
        long long start, elapsed;

        __atomic_store_n(&futex_word, 0, __ATOMIC_RELAXED);
        __atomic_store_n(&futex_ready, 0, __ATOMIC_RELAXED);
        pthread_create(&waiter, NULL, futex_worker, NULL);
        while (!__atomic_load_n(&futex_ready, __ATOMIC_ACQUIRE))
            usleep(1000);
        usleep(20000);
        start = now_ns();
        __atomic_store_n(&futex_word, 1, __ATOMIC_RELEASE);
        syscall(SYS_futex, &futex_word, FUTEX_WAKE, 1, NULL, NULL, 0);
        pthread_join(waiter, NULL);
        elapsed = now_ns() - start;
        check("futex", elapsed < 500000000LL, "futex-wake-latency=%lldus",
              elapsed / 1000);
    }

    return 0;
}

/* ------------------------------------------------------------------ */
/* mm                                                                 */
/* ------------------------------------------------------------------ */

static int test_mm(void)
{
    FILE *f;
    char line[256];
    long memtotal_kb = 0;
    size_t size = 64 * MEM_BLOCK;
    char *mem;
    char *copy;
    long long start, elapsed;
    double mbps;
    size_t i;

    f = fopen("/proc/meminfo", "r");
    if (f) {
        while (fgets(line, sizeof(line), f)) {
            if (sscanf(line, "MemTotal: %ld kB", &memtotal_kb) == 1)
                break;
        }
        fclose(f);
    }

    check("meminfo", memtotal_kb > 1500 * 1024 && memtotal_kb < 4096 * 1024,
          "MemTotal=%ldMB", memtotal_kb / 1024);

    mem = mmap(NULL, size, PROT_READ | PROT_WRITE,
               MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) {
        check("mmap", false, "mmap failed: %s", strerror(errno));
        return 0;
    }
    for (i = 0; i < size; i += 4096)
        mem[i] = (char)(i / 4096);
    check("mmap", true, "touched=%zuMB", size / MEM_BLOCK);

    copy = malloc(size);
    if (copy) {
        start = now_ns();
        memcpy(copy, mem, size);
        elapsed = now_ns() - start;
        mbps = (double)size / 1048576.0 / ((double)elapsed / 1e9);
        check("memcpy", mbps > 100.0, "memcpy=%.1fMB/s", mbps);
        free(copy);
    }

    if (mlock(mem, MEM_BLOCK) == 0) {
        check("mlock", true, "mlocked=1MB");
        munlock(mem, MEM_BLOCK);
    } else {
        check("mlock", false, "mlock failed: %s", strerror(errno));
    }

    if (madvise(mem, size, MADV_DONTNEED) == 0)
        check("madvise", true, "MADV_DONTNEED ok");
    else
        check("madvise", false, "madvise failed: %s", strerror(errno));

    munmap(mem, size);

    {
        FILE *status = fopen("/proc/self/status", "r");
        bool found = false;
        char line[256];

        if (status) {
            while (fgets(line, sizeof(line), status)) {
                if (strncmp(line, "VmRSS:", 6) == 0) {
                    found = true;
                    break;
                }
            }
            fclose(status);
        }
        check("vmrss", found, "VmRSS line in /proc/self/status");
    }

    return 0;
}

/* ------------------------------------------------------------------ */
/* irq                                                                */
/* ------------------------------------------------------------------ */

#define IRQ_SAMPLES 4096

static volatile sig_atomic_t irq_count;
static long long irq_last;
static long long irq_delta[IRQ_SAMPLES];
static int irq_ndelta;

static void irq_handler(int sig)
{
    long long now = now_ns();

    (void)sig;
    if (irq_count > 0 && irq_ndelta < IRQ_SAMPLES) {
        irq_delta[irq_ndelta++] = now - irq_last;
    }
    irq_last = now;
    irq_count++;
}

static int cmp_ll(const void *a, const void *b)
{
    long long x = *(const long long *)a;
    long long y = *(const long long *)b;

    return (x > y) - (x < y);
}

static int test_irq(void)
{
    struct sigevent sev;
    struct itimerspec its;
    struct sigaction sa;
    timer_t timer;
    long long total = 0, max = 0;
    int i;

    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = irq_handler;
    sa.sa_flags = SA_RESTART;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGALRM, &sa, NULL);

    memset(&sev, 0, sizeof(sev));
    sev.sigev_notify = SIGEV_SIGNAL;
    sev.sigev_signo = SIGALRM;
    if (timer_create(CLOCK_MONOTONIC, &sev, &timer) != 0) {
        check("timer", false, "timer_create failed: %s", strerror(errno));
        return 0;
    }
    check("timer", true, "timer_create ok");

    irq_count = 0;
    irq_ndelta = 0;
    irq_last = now_ns();

    its.it_value.tv_sec = 0;
    its.it_value.tv_nsec = 1000000;
    its.it_interval.tv_sec = 0;
    its.it_interval.tv_nsec = 1000000;
    timer_settime(timer, 0, &its, NULL);
    {
        struct timespec start, now;

        clock_gettime(CLOCK_MONOTONIC, &start);
        for (;;) {
            struct timespec req = { .tv_sec = 0, .tv_nsec = 10 * 1000 * 1000 };
            struct timespec rem;
            long long elapsed;

            clock_gettime(CLOCK_MONOTONIC, &now);
            elapsed = (now.tv_sec - start.tv_sec) * 1000000000LL +
                      (now.tv_nsec - start.tv_nsec);
            if (elapsed >= 1500LL * 1000 * 1000)
                break;
            nanosleep(&req, &rem);
        }
    }
    its.it_value.tv_sec = 0;
    its.it_value.tv_nsec = 0;
    its.it_interval.tv_sec = 0;
    its.it_interval.tv_nsec = 0;
    timer_settime(timer, 0, &its, NULL);
    timer_delete(timer);

    check("count", irq_count >= 300, "timer-signals=%d", (int)irq_count);
    if (irq_ndelta > 0) {
        long long avg;

        for (i = 0; i < irq_ndelta; i++)
            total += irq_delta[i];
        qsort(irq_delta, irq_ndelta, sizeof(irq_delta[0]), cmp_ll);
        max = irq_delta[irq_ndelta - 1];
        avg = total / irq_ndelta;
        check("latency", avg < 20000000LL && max < 500000000LL,
              "avg=%lldus max=%lldus samples=%d", avg / 1000, max / 1000,
              irq_ndelta);
    }

    return 0;
}

/* ------------------------------------------------------------------ */
/* rtc                                                                */
/* ------------------------------------------------------------------ */

static int read_rtc_time(int fd, struct rtc_time *tm)
{
    return ioctl(fd, RTC_RD_TIME, tm);
}

static int test_rtc(void)
{
    struct rtc_time tm, back, orig;
    struct timespec sys;
    time_t epoch, sys_epoch;
    char name[128] = "";
    char since[64] = "";
    int fd;

    fd = open("/dev/rtc0", O_RDONLY);
    if (fd < 0) {
        check("open", false, "open /dev/rtc0 failed: %s", strerror(errno));
        return 0;
    }
    check("open", true, "/dev/rtc0 opened");

    if (read_first_line("/sys/class/rtc/rtc0/name", name, sizeof(name)) == 0)
        check("name", strstr(name, "sixlinux_rtc") != NULL, "name=%s", name);
    else
        check("name", false, "cannot read rtc sysfs name");

    if (read_first_line("/sys/class/rtc/rtc0/since_epoch", since, sizeof(since)) == 0)
        check("sysfs", atoll(since) > 1600000000, "since_epoch=%s", since);
    else
        check("sysfs", false, "cannot read rtc since_epoch");

    if (read_rtc_time(fd, &tm) != 0) {
        check("read", false, "RTC_RD_TIME failed: %s", strerror(errno));
        close(fd);
        return 0;
    }
    check("read", true, "RTC_RD_TIME %04d-%02d-%02d %02d:%02d:%02d",
          tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour,
          tm.tm_min, tm.tm_sec);
    check("year", tm.tm_year + 1900 >= 2020 && tm.tm_year + 1900 <= 2100,
          "year=%d", tm.tm_year + 1900);

    {
        struct tm broken;

        memset(&broken, 0, sizeof(broken));
        broken.tm_sec = tm.tm_sec;
        broken.tm_min = tm.tm_min;
        broken.tm_hour = tm.tm_hour;
        broken.tm_mday = tm.tm_mday;
        broken.tm_mon = tm.tm_mon;
        broken.tm_year = tm.tm_year;
        epoch = timegm(&broken);
    }
    clock_gettime(CLOCK_REALTIME, &sys);
    sys_epoch = sys.tv_sec;
    check("delta", llabs((long long)epoch - (long long)sys_epoch) < 86400,
          "rtc_epoch=%lld system_epoch=%lld delta=%llds", (long long)epoch,
          (long long)sys_epoch,
          (long long)epoch - (long long)sys_epoch);

    if (read_rtc_time(fd, &orig) == 0) {
        time_t target = epoch + 60;
        struct tm *gt = gmtime(&target);

        memset(&tm, 0, sizeof(tm));
        tm.tm_sec = gt->tm_sec;
        tm.tm_min = gt->tm_min;
        tm.tm_hour = gt->tm_hour;
        tm.tm_mday = gt->tm_mday;
        tm.tm_mon = gt->tm_mon;
        tm.tm_year = gt->tm_year;

        if (ioctl(fd, RTC_SET_TIME, &tm) != 0) {
            check("set", false, "RTC_SET_TIME failed: %s", strerror(errno));
        } else if (read_rtc_time(fd, &back) != 0) {
            check("set", false, "read back failed: %s", strerror(errno));
        } else {
            struct tm broken;

            memset(&broken, 0, sizeof(broken));
            broken.tm_sec = back.tm_sec;
            broken.tm_min = back.tm_min;
            broken.tm_hour = back.tm_hour;
            broken.tm_mday = back.tm_mday;
            broken.tm_mon = back.tm_mon;
            broken.tm_year = back.tm_year;
            check("set", llabs((long long)timegm(&broken) - (long long)target) <= 2,
                  "RTC_SET_TIME target=%lld readback=%lld", (long long)target,
                  (long long)timegm(&broken));
        }
        ioctl(fd, RTC_SET_TIME, &orig);
    }

    close(fd);
    return 0;
}

/* ------------------------------------------------------------------ */
/* blk                                                                */
/* ------------------------------------------------------------------ */

static int test_blk(void)
{
    unsigned char *buf;
    unsigned char *uncached;
    char *path = "/root/boardtest-io.tmp";
    int fd;
    ssize_t n;
    long long start, elapsed;
    double mbps;
    int i;
    unsigned char sb[8];

    fd = open("/dev/vda", O_RDONLY);
    if (fd < 0) {
        check("device", false, "open /dev/vda failed: %s", strerror(errno));
        return 0;
    }
    if (pread(fd, sb, sizeof(sb), 1024 + 0x38) != (ssize_t)sizeof(sb)) {
        check("device", false, "read ext4 superblock failed");
        close(fd);
        return 0;
    }
    close(fd);
    check("device", sb[0] == 0x53 && sb[1] == 0xef,
          "ext4 magic=0x%02x%02x sectors", sb[1], sb[0]);

    {
        char sizebuf[64];
        long long bytes = 0;

        if (read_first_line("/sys/block/vda/size", sizebuf, sizeof(sizebuf)) == 0) {
            bytes = atoll(sizebuf) * 512;
            check("size", bytes > 100LL * 1024 * 1024, "vda_size=%lldMB",
                  bytes / (1024 * 1024));
        } else {
            check("size", false, "cannot read /sys/block/vda/size");
        }
    }

    buf = malloc(MEM_BLOCK);
    uncached = NULL;
    if (posix_memalign((void **)&uncached, 4096, MEM_BLOCK) != 0)
        uncached = NULL;
    if (!buf) {
        check("file", false, "malloc failed");
        free(uncached);
        return 0;
    }
    memset(buf, 0x5a, MEM_BLOCK);

    fd = open(path, O_CREAT | O_RDWR | O_TRUNC, 0600);
    if (fd < 0) {
        check("file", false, "create %s failed: %s", path, strerror(errno));
        free(buf);
        free(uncached);
        return 0;
    }

    start = now_ns();
    for (i = 0; i < IO_BLOCKS; i++) {
        n = write(fd, buf, MEM_BLOCK);
        if (n != MEM_BLOCK) {
            check("write", false, "write failed at block %d: %s", i,
                  strerror(errno));
            break;
        }
    }
    fsync(fd);
    elapsed = now_ns() - start;
    mbps = (double)IO_BLOCKS / ((double)elapsed / 1e9);
    check("write", mbps > 20.0, "buffered write=%.1fMB/s", mbps);

    lseek(fd, 0, SEEK_SET);
    start = now_ns();
    for (i = 0; i < IO_BLOCKS; i++) {
        n = read(fd, buf, MEM_BLOCK);
        if (n != MEM_BLOCK) {
            check("read", false, "read failed at block %d: %s", i,
                  strerror(errno));
            break;
        }
    }
    elapsed = now_ns() - start;
    mbps = (double)IO_BLOCKS / ((double)elapsed / 1e9);
    check("read", mbps > 20.0, "buffered read=%.1fMB/s", mbps);
    close(fd);
    unlink(path);

    if (uncached) {
        fd = open(path, O_CREAT | O_RDWR | O_TRUNC | O_DIRECT, 0600);
        if (fd >= 0) {
            n = write(fd, uncached, MEM_BLOCK);
            check("odirect", n == MEM_BLOCK, "O_DIRECT write=%zd", n);
            close(fd);
            unlink(path);
        } else {
            check("odirect", false, "O_DIRECT open failed: %s",
                  strerror(errno));
        }
        free(uncached);
    }
    free(buf);

    return 0;
}

/* ------------------------------------------------------------------ */
/* net                                                                */
/* ------------------------------------------------------------------ */

struct tcp_ctx {
    int listen_fd;
    pthread_mutex_t lock;
    pthread_cond_t cond;
    int port;
    int ready;
};

static void *tcp_server(void *arg)
{
    struct tcp_ctx *ctx = arg;
    struct sockaddr_in addr;
    socklen_t len = sizeof(addr);
    char *buf = malloc(MEM_BLOCK);
    long long total = 0;
    int fd;

    pthread_mutex_lock(&ctx->lock);
    /* getsockname 已在主线程完成，这里只需 accept。 */
    pthread_mutex_unlock(&ctx->lock);

    fd = accept(ctx->listen_fd, (struct sockaddr *)&addr, &len);
    if (fd < 0) {
        pthread_mutex_lock(&ctx->lock);
        ctx->ready = -1;
        pthread_cond_signal(&ctx->cond);
        pthread_mutex_unlock(&ctx->lock);
        free(buf);
        return NULL;
    }

    while (buf && total < TCP_BYTES) {
        ssize_t n = read(fd, buf, MEM_BLOCK);

        if (n <= 0)
            break;
        total += n;
    }
    close(fd);
    free(buf);

    pthread_mutex_lock(&ctx->lock);
    ctx->ready = (int)total;
    pthread_cond_signal(&ctx->cond);
    pthread_mutex_unlock(&ctx->lock);
    return NULL;
}

static int http_get(const char *host, int port, const char *path, char *out,
                    size_t outlen)
{
    struct sockaddr_in addr;
    char request[256];
    char *buf = malloc(4096);
    size_t used = 0;
    int fd, ret = -1;

    if (!buf)
        return -1;
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        free(buf);
        return -1;
    }
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    inet_pton(AF_INET, host, &addr.sin_addr);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
        snprintf(request, sizeof(request),
                 "GET %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n",
                 path, host);
        {
            ssize_t ignored = write(fd, request, strlen(request));

            (void)ignored;
        }
        while (used + 1 < 4095) {
            ssize_t n = read(fd, buf + used, 4095 - used);

            if (n <= 0)
                break;
            used += n;
            buf[used] = '\0';
            if (strstr(buf, "sixlinux-boardtest"))
                break;
        }
        if (out && outlen) {
            snprintf(out, outlen, "%s", buf);
        }
        if (strstr(buf, "sixlinux-boardtest") && strstr(buf, "200"))
            ret = 0;
    }
    close(fd);
    free(buf);
    return ret;
}

static int test_net(void)
{
    struct tcp_ctx ctx;
    struct sockaddr_in addr;
    socklen_t alen = sizeof(addr);
    pthread_t server;
    char *buf = malloc(TCP_BYTES);
    long long start, elapsed;
    double mbps;
    int fd, ret;
    char http[256] = "";

    if (!buf) {
        check("tcp", false, "malloc failed");
        return 0;
    }
    memset(buf, 0x33, TCP_BYTES);

    memset(&ctx, 0, sizeof(ctx));
    pthread_mutex_init(&ctx.lock, NULL);
    pthread_cond_init(&ctx.cond, NULL);
    ctx.listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (ctx.listen_fd < 0) {
        check("tcp", false, "socket failed: %s", strerror(errno));
        free(buf);
        return 0;
    }
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    if (bind(ctx.listen_fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 ||
        listen(ctx.listen_fd, 1) != 0 || getsockname(ctx.listen_fd,
                                                    (struct sockaddr *)&addr,
                                                    &alen) != 0) {
        check("tcp", false, "bind/listen failed: %s", strerror(errno));
        close(ctx.listen_fd);
        free(buf);
        return 0;
    }
    ctx.port = ntohs(addr.sin_port);
    pthread_create(&server, NULL, tcp_server, &ctx);

    fd = socket(AF_INET, SOCK_STREAM, 0);
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((uint16_t)ctx.port);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        check("tcp", false, "connect failed: %s", strerror(errno));
        close(fd);
        pthread_cancel(server);
        close(ctx.listen_fd);
        free(buf);
        return 0;
    }

    start = now_ns();
    {
        long long sent = 0;

        while (sent < TCP_BYTES) {
            ssize_t n = write(fd, buf + sent, TCP_BYTES - sent);

            if (n <= 0)
                break;
            sent += n;
        }
        elapsed = now_ns() - start;
        mbps = (double)sent / 1048576.0 / ((double)elapsed / 1e9);
        check("tcp", mbps > 20.0, "loopback tcp=%.1fMB/s", mbps);
    }
    close(fd);
    pthread_join(server, NULL);
    close(ctx.listen_fd);
    check("tcp-bytes", ctx.ready == TCP_BYTES, "server received %d/%d bytes",
          ctx.ready, TCP_BYTES);

    {
        int udp = socket(AF_INET6 == 0 ? AF_INET : AF_INET, SOCK_DGRAM, 0);
        struct sockaddr_in dummy;

        memset(&dummy, 0, sizeof(dummy));
        dummy.sin_family = AF_INET;
        dummy.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        dummy.sin_port = 0;
        if (udp >= 0 && bind(udp, (struct sockaddr *)&dummy, sizeof(dummy)) == 0)
            check("udp", true, "udp loopback socket ok");
        else
            check("udp", false, "udp socket failed");
        if (udp >= 0)
            close(udp);
    }

    ret = http_get("10.0.2.2", 8080, "/boardtest.txt", http, sizeof(http));
    check("http", ret == 0, "GET http://10.0.2.2:8080/boardtest.txt len=%zu",
          strlen(http));

    {
        struct addrinfo hints, *res = NULL;

        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        check("resolve", getaddrinfo("localhost", NULL, &hints, &res) == 0,
              "getaddrinfo(localhost)");
        if (res)
            freeaddrinfo(res);
    }

    free(buf);
    return 0;
}

/* ------------------------------------------------------------------ */
/* systemd                                                            */
/* ------------------------------------------------------------------ */

static int run_capture(const char *command, char *out, size_t outlen)
{
    FILE *p = popen(command, "r");
    size_t used = 0;
    int status;

    if (!p)
        return -1;
    while (used + 1 < outlen) {
        size_t n = fread(out + used, 1, outlen - used - 1, p);

        if (n == 0)
            break;
        used += n;
    }
    out[used] = '\0';
    status = pclose(p);
    return status == 0 ? 0 : -1;
}

static int write_file(const char *path, const char *content)
{
    FILE *f = fopen(path, "w");

    if (!f)
        return -1;
    fputs(content, f);
    fclose(f);
    return 0;
}

static int test_systemd(void)
{
    char out[4096];
    char *service = "/run/systemd/system/sixlinux-boardtest.service";
    const char *unit =
        "[Unit]\n"
        "Description=SixLinux board test service\n"
        "\n"
        "[Service]\n"
        "Type=simple\n"
        "ExecStart=/bin/sh -c 'echo sixlinux-boardtest-marker; exec sleep 30'\n";
    int ok;

    ok = run_capture("systemctl is-system-running 2>/dev/null", out,
                     sizeof(out)) == 0 &&
         strstr(out, "running") != NULL;
    check("state", ok, "systemctl is-system-running=%s", ok ? "running" : out);

    check("unit-write", write_file(service, unit) == 0, "unit=%s", service);
    run_capture("systemctl daemon-reload", out, sizeof(out));
    run_capture("systemctl start sixlinux-boardtest.service", out,
                sizeof(out));
    usleep(500 * 1000);
    ok = run_capture("systemctl is-active sixlinux-boardtest.service 2>/dev/null",
                     out, sizeof(out)) == 0;
    check("service", ok, "is-active=%s", out);

    ok = run_capture("journalctl -u sixlinux-boardtest.service --no-pager -n 5 2>/dev/null",
                     out, sizeof(out)) == 0 &&
         strstr(out, "sixlinux-boardtest-marker") != NULL;
    check("journal", ok, "journald captured service output");

    run_capture("systemctl stop sixlinux-boardtest.service", out, sizeof(out));
    usleep(300 * 1000);
    ok = run_capture("systemctl is-active sixlinux-boardtest.service 2>/dev/null",
                     out, sizeof(out)) != 0;
    check("stop", ok, "is-active after stop=%s", out);

    ok = run_capture("systemd-run --unit=sixlinux-boardtest-timer "
                     "--on-active=1 --timer-property=AccuracySec=100ms "
                     "/bin/sh -c 'echo sixlinux-boardtest-timer-marker' "
                     "2>/dev/null", out, sizeof(out)) == 0;
    if (ok) {
        int i;
        int fired = 0;

        for (i = 0; i < 30; i++) {
            if (run_capture("journalctl -u sixlinux-boardtest-timer "
                            "--no-pager -n 20 2>/dev/null", out,
                            sizeof(out)) == 0 &&
                strstr(out, "sixlinux-boardtest-timer-marker") != NULL) {
                fired = 1;
                break;
            }
            usleep(500 * 1000);
        }
        check("timer", fired, "transient timer fired=%d", fired);
        run_capture("systemctl stop sixlinux-boardtest-timer.timer 2>/dev/null",
                    out, sizeof(out));
        run_capture("systemctl reset-failed sixlinux-boardtest-timer.service 2>/dev/null",
                    out, sizeof(out));
    } else {
        check("timer", false, "systemd-run failed: %s", out);
    }

    unlink(service);
    run_capture("systemctl daemon-reload", out, sizeof(out));
    return 0;
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

struct suite_entry {
    const char *name;
    int (*fn)(void);
};

static const struct suite_entry suite[] = {
    { "cpu", test_cpu },       { "smp", test_smp },
    { "mm", test_mm },         { "irq", test_irq },
    { "rtc", test_rtc },       { "blk", test_blk },
    { "net", test_net },       { "systemd", test_systemd },
};

static int run_entry(const struct suite_entry *entry)
{
    g_test = entry->name;
    g_pass = 0;
    g_fail = 0;
    printf("TEST %s start\n", entry->name);
    fflush(stdout);
    entry->fn();
    printf("SUMMARY %s %s pass=%d fail=%d\n", entry->name,
           g_fail == 0 ? "PASS" : "FAIL", g_pass, g_fail);
    fflush(stdout);
    return g_fail == 0 ? 0 : 1;
}

int main(int argc, char **argv)
{
    size_t i;
    int rc = 0;

    if (argc > 1 && strcmp(argv[1], "--list") == 0) {
        for (i = 0; i < sizeof(suite) / sizeof(suite[0]); i++)
            printf("%s\n", suite[i].name);
        return 0;
    }

    if (argc > 1) {
        for (i = 0; i < sizeof(suite) / sizeof(suite[0]); i++) {
            if (strcmp(argv[1], suite[i].name) == 0)
                return run_entry(&suite[i]);
        }
        fprintf(stderr, "unknown test: %s\n", argv[1]);
        return 2;
    }

    for (i = 0; i < sizeof(suite) / sizeof(suite[0]); i++)
        rc |= run_entry(&suite[i]);
    return rc;
}
