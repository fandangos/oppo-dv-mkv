// oppo-dv-mkv bdregion: Blu-ray region of a disc (the fast first look) and the player's region.
// usage: bdregion detect <BDMV/MovieObject.bdmv>   -> A, B, C, A+B, A+C, B+C or UNKNOWN (HDMV, else BD-J)
//        bdregion hdmv|bdj <BDMV/MovieObject.bdmv> -> the same from one half only
//        bdregion apply <BDMV/MovieObject.bdmv> <player pid>  -> detect, then set the first allowed region
//        bdregion set <player pid> A|B|C|off       -> the player's region (RAM only, until a restart)
//        bdregion wait|gone <path>                 -> return once the path exists / no longer exists
//
// hdmv: every navigation command that reads PSR20 (the player's region) is run in a small simulation three times,
// with PSR20 = A (1), B (2) and C (4), from that command (or up to 4 Set commands before it) for at most 40 steps,
// following the GPRs it sets and the compares, up to the first Play, Jump or Break. Where the three runs end
// differently the spot votes for the regions that are allowed:
//  - some runs jump to a title, others do not          -> the regions that do not jump
//  - no jump, some Break, the others Play or stop      -> the regions that do not Break
//  - all jump to a title, some to a title that only loops on itself (a warning screen) -> the others
// The mask with the most votes wins; a tie is UNKNOWN. Only commands reachable from the start of their movie object
// count. Written for oppo-dv-mkv after the logic of autoABC's region_fast by DamnFine815 (MIT); no code copied.
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MOBJ_MAX  (2u << 20)
#define INDX_MAX  (256u << 10)
#define MAX_OBJ   0x200
#define MAX_CMD   0x2000
#define SIM_STEPS 40
#define PSR20     0x80000014u

static uint8_t mobj[MOBJ_MAX], indx[INDX_MAX];
static uint32_t mlen, ilen, nobj, obj_cmds[MAX_OBJ];
static uint16_t obj_n[MAX_OBJ];

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }

static int loadfile(const char *path, uint8_t *buf, uint32_t max, uint32_t *len)
{
    int fd = open(path, O_RDONLY);
    ssize_t r;
    *len = 0;
    if (fd < 0) return 0;
    while (*len < max && (r = read(fd, buf + *len, max - *len)) > 0) *len += (uint32_t)r;
    close(fd);
    return 1;
}
static const uint8_t *cmd(uint32_t o, uint32_t i) { return mobj + obj_cmds[o] + i * 12; }

// ---- the simulation ------------------------------------------------------------------------------------------------
enum { END_NONE, END_JUMP_TITLE, END_BREAK, END_PLAY, END_JUMP_OTHER };
struct end { int how; uint32_t val; };
static uint8_t gpr_known[0x1000];
static uint32_t gpr_val[0x1000];

// operand 1 (+4, immediate flag 0x80) or 2 (+8, flag 0x40): immediate, PSR20, or a GPR set earlier in the run
static int operand(const uint8_t *c, int which, uint32_t psr20, uint32_t *v)
{
    int imm = which == 1 ? c[1] >> 7 : c[1] >> 6 & 1;
    uint32_t x = be32(c + (which == 1 ? 4 : 8));
    if (imm) { *v = x; return 1; }
    if (x & 0x80000000u) { if ((x & 0x7f) != 0x14) return 0; *v = psr20; return 1; }
    if (!gpr_known[x & 0xfff]) return 0;
    *v = gpr_val[x & 0xfff];
    return 1;
}
static int reads_psr20(const uint8_t *c)
{
    if (c[0] < 0x20) return 0;
    if (!(c[1] & 0x80) && be32(c + 4) == PSR20) return 1;
    return c[0] >= 0x40 && !(c[1] & 0x40) && be32(c + 8) == PSR20;
}
static struct end simulate(uint32_t o, uint32_t i, uint32_t psr20)
{
    struct end e = { END_NONE, 0 };
    uint32_t n = obj_n[o], sets = 0;
    int seen = 0;
    memset(gpr_known, 0, sizeof gpr_known);
    for (int steps = SIM_STEPS; i < n && steps; steps--) {
        const uint8_t *c = cmd(o, i);
        uint32_t g = c[0] >> 3 & 3, sub = c[0] & 7, opt = c[1] & 15, a = 0, b = 0;
        int ka = 1, kb = 1;
        if (c[0] >= 0x20) { ka = operand(c, 1, psr20, &a); if (c[0] >= 0x40) kb = operand(c, 2, psr20, &b); }
        if (reads_psr20(c)) seen = 1;
        if (g == 1) {                                           // compare: true -> next, false -> skip one
            int t;
            if (!ka || !kb) return e;
            switch (c[2] & 15) {
            case 1: t = (a & ~b) == 0; break;
            case 2: t = a == b; break;
            case 3: t = a != b; break;
            case 4: t = a >= b; break;
            case 5: t = a > b; break;
            case 6: t = a <= b; break;
            case 7: t = a < b; break;
            default: t = 1;
            }
            i += t ? 1 : 2;
            continue;
        }
        if (g == 0) {                                           // branch
            if (sub == 2) { if (opt < 3) { e.how = END_PLAY; e.val = ka ? a : 0xffffffffu; return e; } }
            else if (sub == 1) { e.how = opt == 1 ? END_JUMP_TITLE : END_JUMP_OTHER; e.val = ka ? a : 0xffffffffu; return e; }
            else if (sub == 0) {
                if (opt == 1) { if (!ka || a >= n) return e; i = a; continue; }
                if (opt == 2) { e.how = END_BREAK; return e; }
            }
            i++;
            continue;
        }
        if (g == 2 && sub == 0) {                               // Set: follow the GPRs
            uint32_t op = c[3] & 31, v = 0, d = be32(c + 4);
            int unknown = 1;
            if (op == 1) { v = kb ? b : 0; unknown = !kb; }
            else if (ka && kb && op >= 3 && op <= 15) {
                unknown = 0;
                switch (op) {
                case 3: v = a + b < a ? 0xffffffffu : a + b; break;
                case 4: v = a < b ? 0 : a - b; break;
                case 5: { uint64_t m = (uint64_t)a * b; v = m >> 32 ? 0xffffffffu : (uint32_t)m; } break;
                case 9: v = a & b; break;
                case 10: v = a | b; break;
                case 11: v = a ^ b; break;
                case 12: v = a | 1u << (b & 31); break;
                case 13: v = a & ~(1u << (b & 31)); break;
                case 14: v = a << (b & 31); break;
                case 15: v = a >> (b & 31); break;
                default: unknown = 1;                           // divide, modulo, random
                }
            }
            if (!(c[1] & 0x80) && !(d & 0x80000000u)) { gpr_known[d & 0xfff] = !unknown; if (!unknown) gpr_val[d & 0xfff] = v; }
            if (seen && ++sets > 7) return e;
        }
        i++;
    }
    return e;
}

// does title t start (first 16 commands) by jumping to itself?
static int title_selfloop(uint32_t t)
{
    uint32_t s, o, k;
    if (ilen < 16) return 0;
    s = be32(indx + 8);
    if (s + 0x1e > ilen || t - 1 >= be16(indx + s + 0x1c) || s + t * 12 + 0x1e > ilen) return 0;
    if ((indx[s + t * 12 + 0x12] & 0xc0) != 0x40) return 0;
    o = be16(indx + s + t * 12 + 0x18);
    if (o >= nobj) return 0;
    k = obj_n[o] < 16 ? obj_n[o] : 16;
    for (uint32_t i = 0; i < k; i++) {
        const uint8_t *c = cmd(o, i);
        if ((c[0] & 0x1f) == 1 && (c[1] & 0x8f) == 0x81 && be32(c + 4) == t) return 1;
    }
    return 0;
}

static uint8_t reach[MAX_CMD];
static uint16_t stack[MAX_CMD + 1];
static void reachable(uint32_t o)
{
    uint32_t n = obj_n[o], sp = 1;
    memset(reach, 0, n < MAX_CMD ? n : MAX_CMD);
    stack[0] = 0;
    while (sp) {
        uint32_t i = stack[--sp], nx = i + 1;
        const uint8_t *c;
        if (i >= n || reach[i]) continue;
        reach[i] = 1;
        c = cmd(o, i);
        if ((c[0] >> 3 & 3) == 1) {                             // compare: both ways
            if (nx < n) stack[sp++] = (uint16_t)nx;
            if (i + 2 < n && sp < MAX_CMD) stack[sp++] = (uint16_t)(i + 2);
            continue;
        }
        if ((c[0] >> 3 & 3) == 0 && (c[0] & 7) == 0) {          // GoTo / Break / Nop
            uint32_t opt = c[1] & 15, d = be32(c + 4);
            if (opt) { if (opt == 1 && (c[1] & 0x80) && d < n) stack[sp++] = (uint16_t)d; continue; }
        } else if ((c[0] >> 3 & 3) == 0 && (c[0] & 7) == 1) continue;   // a jump ends the path
        if (nx < n) stack[sp++] = (uint16_t)nx;
    }
}

static int detect_hdmv(const char *path)
{
    static const char suffix[] = "MovieObject.bdmv";
    uint32_t votes[7] = { 0 }, off = 0x32, best = 0, bi = 0;
    int tie = 0;
    size_t len = strlen(path), sl = sizeof suffix - 1;
    if (!loadfile(path, mobj, MOBJ_MAX, &mlen) || mlen < 0x32 || memcmp(mobj, "MOBJ", 4)) return 0;
    nobj = be16(mobj + 0x30);
    if (nobj > MAX_OBJ) return 0;
    for (uint32_t o = 0; o < nobj; o++) {
        uint32_t n;
        if (off + 4 > mlen) return 0;
        n = be16(mobj + off + 2);
        if (off + 4 + n * 12 > mlen) return 0;
        obj_cmds[o] = off + 4; obj_n[o] = (uint16_t)n; off += 4 + n * 12;
    }
    ilen = 0;
    if (len >= sl && !strcmp(path + len - sl, suffix) && len - sl < 0x3ff) {
        char ip[0x400 + 16];
        memcpy(ip, path, len - sl); strcpy(ip + len - sl, "index.bdmv");
        loadfile(ip, indx, INDX_MAX, &ilen);
    }
    for (uint32_t o = 0; o < nobj; o++) {
        uint32_t n = obj_n[o], prev = 0xffff;
        int all = n == 0 || n > MAX_CMD;
        if (!all) reachable(o);
        for (uint32_t k = 0; k < n; k++) {
            uint32_t st, s, mask = 0;
            struct end r[3];
            int any1 = 0, not1 = 0, any2 = 0, any30 = 0, all1 = 1;
            if (!all && !reach[k]) continue;
            if (!reads_psr20(cmd(o, k))) continue;
            st = k;
            if ((cmd(o, k)[0] & 0x18) != 8)                     // not a compare: start at the Set commands before it
                for (s = k; s && (int)s > (int)k - 4 && (cmd(o, s - 1)[0] & 0x1f) == 0x10; s--) st = s - 1;
            if (st == prev) continue;
            prev = st;
            r[0] = simulate(o, st, 1); r[1] = simulate(o, st, 2); r[2] = simulate(o, st, 4);
            if (r[0].how == r[1].how && r[1].how == r[2].how && r[0].val == r[1].val && r[1].val == r[2].val) continue;
            for (int i = 0; i < 3; i++) {
                int h = r[i].how;
                if (h != END_JUMP_TITLE) { not1 = 1; all1 = 0; } else any1 = 1;
                if (h == END_BREAK) any2 = 1;
                if (h == END_PLAY || h == END_NONE) any30 = 1;
            }
            if (any1 && not1) { for (int i = 0; i < 3; i++) if (r[i].how != END_JUMP_TITLE) mask |= 1u << i; }
            else if (!any1 && any2 && any30) { for (int i = 0; i < 3; i++) if (r[i].how != END_BREAK) mask |= 1u << i; }
            else if (all1) {
                int l0 = title_selfloop(r[0].val), l1 = title_selfloop(r[1].val), l2 = title_selfloop(r[2].val);
                if (!(l0 || l1 || l2) || (l0 && l1 && l2)) continue;
                mask = (uint32_t)(!l0) | (uint32_t)(!l1) << 1 | (uint32_t)(!l2) << 2;
            } else continue;
            if (mask >= 1 && mask <= 6) votes[mask]++;
        }
    }
    for (uint32_t m = 1; m <= 6; m++) {
        if (votes[m] && votes[m] == best) tie = 1;
        if (votes[m] > best) { best = votes[m]; bi = m; tie = 0; }
    }
    return tie ? 0 : (int)bi;
}

#include "bdj.c"

// ---- the player's region: CBR byte 0x12346fc of the player program (1 A, 2 B, 3 C, 0xff the player's own) ----------
#define CBR 0x12346fcu
static int set_region(const char *pid, int v)
{
    char p[64];
    unsigned char b = (unsigned char)v, cur = 0;
    int fd, ok;
    if (strlen(pid) > 20 || strspn(pid, "0123456789") != strlen(pid)) return 0;
    snprintf(p, sizeof p, "/proc/%s/mem", pid);
    if ((fd = open(p, O_RDWR)) < 0) return 0;
    ok = pread(fd, &cur, 1, CBR) == 1 && (cur == 1 || cur == 2 || cur == 3 || cur == 0xff)
         && pwrite(fd, &b, 1, CBR) == 1;
    close(fd);
    return ok;
}

static const char *const MASKS[7] = { "UNKNOWN", "A", "B", "A+B", "C", "A+C", "B+C" };
static int region_of(int m) { return m & 1 ? 1 : m & 2 ? 2 : m & 4 ? 3 : 0; }
int main(int argc, char **argv)
{
    const char *c = argc > 1 ? argv[1] : "";
    if (argc < 3) goto usage;
    if (!strcmp(c, "detect") || !strcmp(c, "hdmv") || !strcmp(c, "bdj")) {
        int m = !strcmp(c, "bdj") ? 0 : detect_hdmv(argv[2]);
        if (!m && strcmp(c, "hdmv")) m = (int)detect_bdj(argv[2]);
        if (m < 0 || m > 6) m = 0;
        puts(MASKS[m]);
        return m ? 0 : 1;
    }
    if (!strcmp(c, "wait") || !strcmp(c, "gone")) {
        int want = !strcmp(c, "wait");
        while ((access(argv[2], F_OK) == 0) != want) usleep(100000);
        return 0;
    }
    if (!strcmp(c, "apply")) {
        int m, r;
        if (argc < 4) return 2;
        m = detect_hdmv(argv[2]);
        if (!m) m = (int)detect_bdj(argv[2]);
        if (m < 1 || m > 6) { puts("UNKNOWN"); return 1; }
        r = region_of(m);
        if (!set_region(argv[3], r)) { puts("SET_ERROR"); return 3; }
        puts(r == 1 ? "A" : r == 2 ? "B" : "C");
        return 0;
    }
    if (!strcmp(c, "set") && argc == 4) {
        const char *r = argv[3];
        int v = !strcmp(r, "A") || !strcmp(r, "a") ? 1 : !strcmp(r, "B") || !strcmp(r, "b") ? 2
              : !strcmp(r, "C") || !strcmp(r, "c") ? 3 : !strcmp(r, "off") ? 0xff : 0;
        if (!v) return 2;
        if (!set_region(argv[2], v)) { puts("SET_ERROR"); return 3; }
        return 0;
    }
usage:
    fputs("usage: bdregion detect|hdmv|bdj <BDMV/MovieObject.bdmv> | apply <MovieObject.bdmv> <pid>"
          " | set <pid> A|B|C|off | wait|gone <path>\n", stderr);
    return 2;
}
