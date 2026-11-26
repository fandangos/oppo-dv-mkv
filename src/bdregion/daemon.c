// oppo-dv-mkv bdregiond: sets the player's Blu-ray region for each disc it plays (option bd_region).
// usage: bdregiond <player pid> <folder with bdregion, bdhdmv, bdcallgraph>     (started by bdregion.sh on)
// Works with the hook at 0x1c03a00 (hook/hook.c): its header says whether it is enabled (the Extras switch), holds
// the PSR20 mailbox for BD-J on a physical disc and the requests for disc images and folders.
//  - a physical disc appears (/mnt/disc_00_0 or /mnt/sr0): bdregion detect, an A/B/C answer checked by bdhdmv (it
//    wins when it disagrees); A/B/C -> the player's region (CBR) and the same answer in the mailbox; unknown -> bdhdmv;
//    still unknown -> nothing until the disc's BD-J asks for PSR20 (the hook posts REQUEST): bdcallgraph answers
//    through the mailbox (or PASS)
//  - an image was mounted on /mnt/iso or a folder linked to /mnt/link (the hook waits for us): the same, with
//    bdcallgraph at once; then the player goes on
//  - the disc is taken out, the image unmounted, or the switch turned off: the player's own region. The player keeps
//    /mnt/link after a stop (until the next folder), so each new disc, image or folder starts from the player's own
//    region and decides again: the region only matters when a disc loads, and every load goes through here
// The region is set in RAM only (CBR byte 0x12346fc: 1 A, 2 B, 3 C, 0xff the player's setting); a restart clears it.
// Written for oppo-dv-mkv after autoABC by DamnFine815 (MIT); no code copied.
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include "hook/hook.h"

#define CBR 0x12346fcu
#define OFF(f) (BDR_BASE + (uint32_t)__builtin_offsetof(struct bdr_hdr, f))
static int mem = -1, pid;
static const char *tools;
static FILE *lg;

static void logf_(const char *fmt, const char *a, const char *b)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    if (!lg) return;
    fprintf(lg, "[%ld.%02ld] ", (long)t.tv_sec, t.tv_nsec / 10000000);
    fprintf(lg, fmt, a ? a : "", b ? b : "");
    fputc('\n', lg); fflush(lg);
}
static uint32_t rd(uint32_t a) { uint32_t v = 0; if (pread(mem, &v, 4, a) != 4) return 0xdeadbeefu; return v; }
static void wr(uint32_t a, uint32_t v) { (void)!pwrite(mem, &v, 4, a); }
static int exists(const char *p) { struct stat st; return stat(p, &st) == 0; }

// the player's region: 'A' 'B' 'C' or 0 (its own setting)
static int cur_set;
static void set_region(int r)
{
    unsigned char b = r == 'A' ? 1 : r == 'B' ? 2 : r == 'C' ? 3 : 0xff, c = 0;
    if (pread(mem, &c, 1, CBR) != 1 || !(c == 1 || c == 2 || c == 3 || c == 0xff)) { logf_("region byte %s unexpected: not touched", "", 0); return; }
    if (c != b) (void)!pwrite(mem, &b, 1, CBR);
    cur_set = r;
}

// one line from a tool: tool [a1] [a2]
static int run(const char *tool, const char *a1, const char *a2, char *out, size_t n)
{
    int fd[2], st;
    pid_t c;
    ssize_t k = 0, r;
    char path[512];
    out[0] = 0;
    snprintf(path, sizeof path, "%s/%s", tools, tool);
    if (pipe(fd)) return 0;
    if ((c = fork()) == 0) {
        dup2(fd[1], 1); close(fd[0]); close(fd[1]);
        if (a2) execl(path, tool, a1, a2, (char *)0); else execl(path, tool, a1, (char *)0);
        _exit(127);
    }
    close(fd[1]);
    if (c < 0) { close(fd[0]); return 0; }
    while ((size_t)k + 1 < n && (r = read(fd[0], out + k, n - 1 - (size_t)k)) > 0) k += r;
    close(fd[0]);
    waitpid(c, &st, 0);
    out[k] = 0;
    out[strcspn(out, "\r\n")] = 0;
    return 1;
}
// "A", "A+B", "1".."7" ... -> the first allowed region, 'F' region free, 0 unknown
static int region_of(const char *s)
{
    if (!strcmp(s, "7")) return 'F';
    if (s[0] >= '1' && s[0] <= '6' && !s[1]) { int m = s[0] - '0'; return m & 1 ? 'A' : m & 2 ? 'B' : 'C'; }
    if (s[0] == 'A' || s[0] == 'B' || s[0] == 'C') return s[0];
    return 0;
}
static int bit_of(int r) { return r == 'A' ? 1 : r == 'B' ? 2 : r == 'C' ? 4 : 0; }

// bdregion detect, checked or completed by bdhdmv; with cg also bdcallgraph. 'A' 'B' 'C', 'F' free, 0 unknown
static int decide(const char *mobj, int cg, char *how, size_t hn)
{
    char o[64], h[64], c[64];
    int r, hr;
    run("bdregion", "detect", mobj, o, sizeof o);
    r = region_of(o);
    run("bdhdmv", mobj, 0, h, sizeof h);
    hr = region_of(h);
    if (r && hr && hr != r) { snprintf(how, hn, "detect %s, hdmv %s (hdmv wins)", o, h); return hr; }
    if (r) { snprintf(how, hn, "detect %s", o); return r; }
    if (hr) { snprintf(how, hn, "hdmv %s", h); return hr; }
    if (!cg) { snprintf(how, hn, "unknown so far"); return 0; }
    run("bdcallgraph", mobj, 0, c, sizeof c);
    snprintf(how, hn, "callgraph %s", c);
    return region_of(c);
}
static const char *rname(int r) { return r == 'A' ? "A" : r == 'B' ? "B" : r == 'C' ? "C" : r == 'F' ? "free" : "unknown"; }

static const char *const DISC[2] = { "/mnt/disc_00_0/BDMV/MovieObject.bdmv", "/mnt/sr0/BDMV/MovieObject.bdmv" };
static const char *disc(void) { for (int i = 0; i < 2; i++) if (exists(DISC[i])) return DISC[i]; return 0; }

int main(int argc, char **argv)
{
    char p[64], how[160], vsrc[600] = "";
    int phys = 0, pending = 0, virt = 0, en_last = -1;
    if (argc != 3) { fputs("usage: bdregiond <player pid> <tools folder>\n", stderr); return 2; }
    pid = atoi(argv[1]); tools = argv[2];
    snprintf(p, sizeof p, "/proc/%d/mem", pid);
    if ((mem = open(p, O_RDWR)) < 0) return 1;
    if (rd(BDR_BASE) != BDR_MAGIC) return 1;
    snprintf(how, sizeof how, "%s/log", tools);
    lg = fopen(how, "a");
    signal(SIGPIPE, SIG_IGN);
    logf_("start (player %s)", argv[1], 0);
    for (;;) {
        uint32_t en, v;
        const char *d;
        usleep(10000);
        if (kill(pid, 0) || rd(BDR_BASE) != BDR_MAGIC) { logf_("player or hook gone: stop", 0, 0); return 0; }
        en = rd(OFF(enable));
        if ((int)en != en_last) { logf_(en ? "switched on" : "switched off", 0, 0); en_last = (int)en; }
        if (!en) {
            if (cur_set) set_region(0);
            phys = pending = virt = 0;
            continue;
        }
        // a disc image mounted / a folder linked: the player waits for us
        if ((v = rd(OFF(vreq)))) {
            char m[600];
            int r = 0;
            m[0] = 0;
            if (v == 1 && exists("/mnt/iso/BDMV/MovieObject.bdmv")) snprintf(m, sizeof m, "/mnt/iso/BDMV/MovieObject.bdmv");
            else if (v == 2) {
                char t[512];
                ssize_t k = readlink("/mnt/link", t, sizeof t - 1);
                if (k > 0) { t[k] = 0; snprintf(m, sizeof m, "%s/BDMV/MovieObject.bdmv", t); if (!exists(m)) m[0] = 0; }
            }
            if (m[0]) {
                r = decide(m, 1, how, sizeof how);
                set_region(r == 'F' ? 0 : r);
                virt = 1; snprintf(vsrc, sizeof vsrc, "%s", v == 1 ? "/mnt/iso/BDMV/MovieObject.bdmv" : "/mnt/link");
                logf_("image/folder: region %s", rname(r), how);
                logf_("  (%s)", how, 0);
            }
            wr(OFF(vreq), 0);
        }
        if (virt && !exists(vsrc)) { virt = 0; if (!phys) set_region(0); logf_("image/folder gone: the player's own region", 0, 0); }
        // a physical disc
        d = disc();
        if (d && !phys) {
            int r;
            phys = 1; pending = 0;
            wr(OFF(mailbox), MB_EMPTY);
            set_region(0);                                  // every disc starts from the player's own region
            r = decide(d, 0, how, sizeof how);
            if (r == 'A' || r == 'B' || r == 'C') { set_region(r); wr(OFF(mailbox), (uint32_t)bit_of(r)); }
            else pending = 1;
            logf_("disc: region %s", rname(r), 0);
            logf_("  (%s)", how, 0);
        }
        if (d && pending && rd(OFF(mailbox)) == MB_REQUEST) {
            char c[64];
            int r;
            run("bdcallgraph", d, 0, c, sizeof c);
            r = region_of(c);
            wr(OFF(mailbox), r == 'A' || r == 'B' || r == 'C' ? (uint32_t)bit_of(r) : MB_PASS);
            pending = 0;
            logf_("disc asked for its region (BD-J): %s (callgraph %s)", rname(r), c);
        }
        if (!d && phys) {
            phys = pending = 0;
            wr(OFF(mailbox), MB_EMPTY);
            if (!virt) set_region(0);
            logf_("disc gone: the player's own region", 0, 0);
        }
    }
}
