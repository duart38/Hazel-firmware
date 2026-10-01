/* unb64 FILE: decode base64 from stdin into FILE, stop at '.', print "unb64 OK <bytes>".
 * The fast upload path (tools/x1d_push.py): the camera has no base64 tool, and the USB shell can
 * stream text into a running program. No libc at all, only system calls, so it runs on any
 * firmware. Build: camera-lib/build-exe.sh unb64.c */

#define SYS_EXIT 1
#define SYS_READ 3
#define SYS_WRITE 4
#define SYS_OPEN 5
#define SYS_CLOSE 6

static long sys3(long n, long a, long b, long c) {
    register long r7 __asm__("r7") = n;
    register long r0 __asm__("r0") = a;
    register long r1 __asm__("r1") = b;
    register long r2 __asm__("r2") = c;
    __asm__ volatile("svc #0" : "+r"(r0) : "r"(r7), "r"(r1), "r"(r2) : "memory");
    return r0;
}

static void say(const char *text) {
    int n = 0;
    while (text[n]) n++;
    sys3(SYS_WRITE, 1, (long)text, n);
}

static int value(int c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static unsigned char in[4096], out[4096];

__attribute__((used, noreturn)) void run(int argc, char **argv);
__attribute__((used, noreturn)) void run(int argc, char **argv) {
    if (argc != 2) { say("usage: unb64 FILE\n"); sys3(SYS_EXIT, 2, 0, 0); }
    int fd = (int)sys3(SYS_OPEN, (long)argv[1], 01 | 0100 | 01000, 0644); /* write, create, truncate */
    if (fd < 0) { say("unb64: cannot open file\n"); sys3(SYS_EXIT, 1, 0, 0); }
    say("unb64 READY\n");
    unsigned int bits = 0, total = 0;
    int nbits = 0, done = 0;
    while (!done) {
        long got = sys3(SYS_READ, 0, (long)in, sizeof in);
        if (got <= 0) break;
        int o = 0;
        for (long i = 0; i < got; i++) {
            if (in[i] == '.') { done = 1; break; }
            int v = value(in[i]);
            if (v < 0) continue; /* newlines, padding */
            bits = (bits << 6) | (unsigned int)v;
            nbits += 6;
            if (nbits >= 8) {
                nbits -= 8;
                out[o++] = (unsigned char)(bits >> nbits);
            }
        }
        if (o && sys3(SYS_WRITE, fd, (long)out, o) != o) { say("unb64: write failed\n"); sys3(SYS_EXIT, 1, 0, 0); }
        total += (unsigned int)o;
    }
    sys3(SYS_CLOSE, fd, 0, 0);
    char msg[32] = "unb64 OK ";
    char digits[12];
    int n = 0, m = 9;
    do { digits[n++] = (char)('0' + total % 10); total /= 10; } while (total);
    while (n) msg[m++] = digits[--n];
    msg[m++] = '\n';
    msg[m] = 0;
    say(msg);
    sys3(SYS_EXIT, done ? 0 : 1, 0, 0);
    __builtin_unreachable();
}

/* the kernel starts us with argc and argv on the stack */
__attribute__((naked, noreturn)) void _start(void) {
    __asm__ volatile("ldr r0, [sp]\n add r1, sp, #4\n bl run\n");
}
