// oppo-dv-mkv bdcallgraph: Blu-ray region of a BD-J disc from the call graph of its Java code (all .jar files in
// BDMV/JAR), for discs where the quick look (bdregion) finds nothing. Prints the region mask as one digit (1 A, 2 B,
// 3 A+B, 4 C, 5 A+C, 6 B+C, 7 region free) or UNKNOWN.
// usage: bdcallgraph <path to BDMV/MovieObject.bdmv>
//
// Written for oppo-dv-mkv after the logic of autoABC's region_bdj_callgraph by DamnFine815 (MIT); no code copied.
// Every class of every .jar is read; methods are known by a hash of class, name and descriptor. Three kinds matter:
//  - "(I)I" methods that pass their int parameter on to RegisterAccess.getPSR, or to such a method: they read a PSR
//  - "()I"  methods that call one of those with the constant 20: they return the player's region (PSR20)
//  - "(I)Z" methods that behave like "return (r & regionMethod()) != 0" for r and the region in {1, 2, 4} (checked
//    by running their code nine times, with the ()I call answered): they check whether region r is the player's
// The disc's allowed regions are what it passes to such a check, followed by ifeq/ifne: a constant 1..7, or a field
// that a constructor fills with "new int[] { regions }" (each element a constant 1..7). Fields win over constants;
// a field filled differently in two places, or two fields that disagree, make it UNKNOWN.
#include <dirent.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "inflate.h"

#define JAR_MAX  (4u << 20)
#define CLS_MAX  0x80000
#define CP_MAX   0x1000
#define MAX_METH 1400
#define MAX_FLD  256
#define MAX_CALL 768
#define FNV0     0x811c9dc5u
#define FNVP     0x1000193u

static uint8_t jar[JAR_MAX], cls[CLS_MAX];
static uint32_t jlen, clen;
static uint16_t cpcount, cp_a[CP_MAX], cp_b[CP_MAX], cp_len[CP_MAX];
static uint8_t cp_tag[CP_MAX];
static uint32_t cp_off[CP_MAX], cp_int[CP_MAX];

enum { K_NONE, K_READ, K_REGION, K_CHECK };     // (I)I reads a PSR, ()I returns the region, (I)Z checks a region
struct meth { uint32_t hash; uint8_t kind, direct, reads, region, check, n[3]; uint32_t callee[3][4]; };
static struct meth meths[MAX_METH];
static uint32_t nmeth;
struct fld { uint32_t hash; uint8_t val, conflict; };
static struct fld flds[MAX_FLD];
static uint32_t nfld;
struct call { uint32_t sig, field; uint16_t val; uint8_t kind; };   // kind 1 through a field, 2 a constant
static struct call calls[MAX_CALL];
static uint32_t ncall;

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }

// ---- constant pool helpers ------------------------------------------------------------------------------------------
static int utf_ok(uint32_t i) { return i && i < cpcount && cp_tag[i] == 1; }
static int cp_eq(uint32_t i, const char *s)
{
    size_t k = strlen(s);
    return utf_ok(i) && cp_len[i] == k && k && !memcmp(cls + cp_off[i], s, k);
}
static int mem_ci(const uint8_t *m, uint32_t n, const char *s)
{
    size_t k = strlen(s);
    if (!k || k > n) return 0;
    for (uint32_t i = 0; i + k <= n; i++) {
        size_t j = 0;
        for (; j < k; j++) {
            uint8_t a = m[i + j], b = (uint8_t)s[j];
            if (a >= 'A' && a <= 'Z') a += 32;
            if (b >= 'A' && b <= 'Z') b += 32;
            if (a != b) break;
        }
        if (j == k) return 1;
    }
    return 0;
}
static int cp_has(uint32_t i, const char *s) { return utf_ok(i) && mem_ci(cls + cp_off[i], cp_len[i], s); }
static uint32_t utfhash(uint32_t i, uint32_t h)
{
    if (!i || i >= cpcount) return 0;
    if (cp_tag[i] != 1) return 0;
    for (uint32_t k = 0; k < cp_len[i]; k++) h = (h ^ cls[cp_off[i] + k]) * FNVP;
    return h;
}
static uint32_t sighash(uint32_t ci, uint32_t name, uint32_t desc)
{
    uint32_t h;
    if (!ci || ci >= cpcount || cp_tag[ci] != 7 || !cp_a[ci]) return 0;
    h = utfhash(cp_a[ci], FNV0);
    h = utfhash(name, (h ^ 0xff) * FNVP);
    return utfhash(desc, (h ^ 0xff) * FNVP);
}
// Fieldref / Methodref / InterfaceMethodref -> class, name, descriptor
static int ref_parts(uint32_t r, uint32_t *c, uint32_t *n, uint32_t *d)
{
    uint32_t nt;
    if (!r || r >= cpcount || cp_tag[r] < 9 || cp_tag[r] > 11) return 0;
    *c = cp_a[r]; nt = cp_b[r];
    if (!nt || nt >= cpcount || cp_tag[nt] != 12) return 0;
    *n = cp_a[nt]; *d = cp_b[nt];
    return 1;
}
static uint32_t ref_sig(uint32_t r) { uint32_t c, n, d; return ref_parts(r, &c, &n, &d) ? sighash(c, n, d) : 0; }
static uint32_t ref_field(uint32_t r)
{
    uint32_t c, n, d, h;
    if (!ref_parts(r, &c, &n, &d) || cp_tag[r] != 9) return 0;
    if (!c || c >= cpcount || cp_tag[c] != 7 || !cp_a[c]) return 0;
    h = utfhash(cp_a[c], FNV0);
    return utfhash(n, (h ^ 0xff) * FNVP);
}
static int desc_kind(uint32_t d) { return cp_eq(d, "(I)I") ? K_READ : cp_eq(d, "()I") ? K_REGION : cp_eq(d, "(I)Z") ? K_CHECK : K_NONE; }
static int ref_kind(uint32_t r) { uint32_t c, n, d; return ref_parts(r, &c, &n, &d) ? desc_kind(d) : 0; }

// ---- one instruction ----------------------------------------------------------------------------------------------
struct insn { uint32_t pc, len; uint8_t op; uint32_t isconst, val, local; uint16_t cpi; };
static void idec(struct insn *in, const uint8_t *code, uint32_t n, uint32_t pc)
{
    uint32_t len = 1, end, op;
    memset(in, 0, sizeof *in);
    in->pc = pc; in->local = 0xffffffffu;
    if (pc >= n) return;
    op = code[pc]; in->op = (uint8_t)op;
    switch (op) {
    case 0x84: case 0x99: case 0x9a: case 0x9b: case 0x9c: case 0x9d: case 0x9e: case 0x9f: case 0xa0: case 0xa1:
    case 0xa2: case 0xa3: case 0xa4: case 0xa5: case 0xa6: case 0xa7: case 0xa8: case 0xb2: case 0xb3: case 0xb4:
    case 0xb5: case 0xb6: case 0xb7: case 0xb8: case 0xbb: case 0xbd: case 0xc0: case 0xc1: case 0x11: case 0x13:
    case 0x14:
        len = pc + 3 <= n ? 3 : 0; break;
    case 0x10: case 0x12: case 0x15: case 0x16: case 0x17: case 0x18: case 0x19: case 0x36: case 0x37: case 0x38:
    case 0x39: case 0x3a: case 0xa9: case 0xbc:
        len = pc + 2 <= n ? 2 : 0; break;
    case 0xaa: {
        uint32_t a = pc & ~3u, lo, hi;
        len = 0;
        if (a + 16 <= n) { lo = be32(code + a + 8); hi = be32(code + a + 12); if (lo <= hi && hi - lo <= 0x1000) { end = a + (hi - lo) * 4 + 20; len = end <= n ? end - pc : 0; } }
        break;
    }
    case 0xab: {
        uint32_t a = (pc & ~3u) + 12, np;
        len = 0;
        if (a <= n && (np = be32(code + a - 4)) <= 0x1000) { end = a + np * 8; len = end <= n ? end - pc : 0; }
        break;
    }
    case 0xb9: case 0xba: case 0xc8: case 0xc9:
        len = pc + 5 <= n ? 5 : 0; break;
    case 0xc4:
        len = pc + 2 > n ? 0 : code[pc + 1] == 0x84 ? (pc + 6 <= n ? 6 : 0) : (pc + 4 <= n ? 4 : 0); break;
    case 0xc5:
        len = pc + 4 <= n ? 4 : 0; break;
    default: len = 1;
    }
    in->len = len;
    if (!len) return;
    if (op >= 3 && op <= 8) { in->isconst = 1; in->val = op - 3; return; }
    if (op == 2) { in->isconst = 1; in->val = 0xffffffffu; return; }
    if (op == 0x10) { in->isconst = 1; in->val = (uint32_t)(int8_t)code[pc + 1]; return; }
    if (op == 0x11) { in->isconst = 1; in->val = (uint32_t)(int16_t)be16(code + pc + 1); return; }
    if (op == 0x12 || op == 0x13) {
        uint32_t i = op == 0x12 ? code[pc + 1] : be16(code + pc + 1);
        in->cpi = (uint16_t)i;
        if (i && i < cpcount && cp_tag[i] == 3) { in->isconst = 1; in->val = cp_int[i]; }
        return;
    }
    if (op == 0x15 || op == 0x36) { in->local = code[pc + 1]; return; }
    if (op >= 0x1a && op <= 0x1d) { in->local = op - 0x1a; return; }
    if (op >= 0x3b && op <= 0x3e) { in->local = op - 0x3b; return; }
    if (op >= 0xb2 && op <= 0xb9) in->cpi = be16(code + pc + 1);
}

// ---- tables ---------------------------------------------------------------------------------------------------------
static struct meth *meth_get(uint32_t h, int kind)
{
    for (uint32_t i = 0; i < nmeth; i++) if (meths[i].hash == h) return &meths[i];
    if (nmeth >= MAX_METH) return 0;
    memset(&meths[nmeth], 0, sizeof meths[0]);
    meths[nmeth].hash = h; meths[nmeth].kind = (uint8_t)kind;
    return &meths[nmeth++];
}
static void add_callee(struct meth *m, int list, uint32_t sig)
{
    uint8_t c = m->n[list];
    for (uint32_t i = 0; i < c; i++) if (m->callee[list][i] == sig) return;
    if (c >= 4) return;
    m->callee[list][c] = sig; m->n[list] = (uint8_t)(c + 1);
}

// "return (r & regionMethod()) != 0": run the code for r and the region in {1, 2, 4}
static int is_check(const uint8_t *code, uint32_t n, uint32_t param, uint32_t site)
{
    for (uint32_t reg = 1; reg <= 4; reg <<= 1)
        for (uint32_t r = 1; r <= 4; r <<= 1) {
            uint32_t loc[8] = { 0 }, st[24], sp = 0, pc = 0, budget = 0x81, top;
            int done = 0;
            loc[param] = r;
            while (!done) {
                struct insn in;
                uint32_t step;
                if (--budget == 0) return 0;
                idec(&in, code, n, pc);
                if (!in.len) return 0;
                step = in.len;
                if (in.isconst) { if (sp >= 24) return 0; st[sp++] = in.val; }
                else {
                    uint8_t op = in.op;
                    if (op == 0x15 || (op >= 0x1a && op <= 0x1d)) { if (in.local >= 8 || sp >= 24) return 0; st[sp++] = loc[in.local]; }
                    else if (op == 0x36 || (op >= 0x3b && op <= 0x3e)) { if (in.local >= 8 || !sp) return 0; loc[in.local] = st[--sp]; }
                    else if (op == 0x60 || op == 0x64 || op == 0x68 || op == 0x7e || op == 0x80 || op == 0x82) {
                        uint32_t a, b;
                        if (sp < 2) return 0;
                        a = st[sp - 2]; b = st[sp - 1];
                        st[sp - 2] = op == 0x60 ? a + b : op == 0x64 ? a - b : op == 0x68 ? a * b : op == 0x7e ? a & b : op == 0x80 ? a | b : a ^ b;
                        sp--;
                    } else if (op >= 0x99 && op <= 0x9e) {
                        int32_t v; int t;
                        if (!sp) return 0;
                        v = (int32_t)st[--sp];
                        t = op == 0x99 ? v == 0 : op == 0x9a ? v != 0 : op == 0x9b ? v < 0 : op == 0x9c ? v >= 0 : op == 0x9d ? v > 0 : v < 1;
                        if (t) step = (uint32_t)(int16_t)be16(code + pc + 1);
                    } else if (op >= 0x9f && op <= 0xa4) {
                        int32_t a, b; int t;
                        if (sp < 2) return 0;
                        a = (int32_t)st[sp - 2]; b = (int32_t)st[sp - 1]; sp -= 2;
                        t = op == 0x9f ? a == b : op == 0xa0 ? a != b : op == 0xa1 ? a < b : op == 0xa2 ? a >= b : op == 0xa3 ? a > b : a <= b;
                        if (t) step = (uint32_t)(int16_t)be16(code + pc + 1);
                    } else if (op == 0xa7) step = (uint32_t)(int16_t)be16(code + pc + 1);
                    else if (op == 0xac) {
                        if (!sp) return 0;
                        top = st[sp - 1];
                        if (((r & reg) != 0) != (top != 0)) return 0;
                        done = 1;
                        continue;
                    } else if (op == 0xb6 || op == 0xb8) {
                        if (in.cpi != site || sp >= 24) return 0;     // the same constant pool entry as the call site
                        st[sp++] = reg;
                    } else return 0;
                }
                pc += step;
                if (pc >= n) return 0;
            }
        }
    return 1;
}

// ---- one class ----------------------------------------------------------------------------------------------------
static void do_class(void)
{
    uint32_t n = clen, p = 10, cnt, this_cls, q, mc;
    if (n < 10 || be32(cls) != 0xcafebabe || (cnt = be16(cls + 8)) == 0 || cnt > CP_MAX) return;
    cpcount = (uint16_t)cnt;
    for (uint32_t i = 0; i < cnt; i++) { cp_tag[i] = 0; cp_off[i] = cp_int[i] = 0; cp_len[i] = cp_a[i] = cp_b[i] = 0; }
    for (uint32_t i = 1; i < cnt; i++) {
        uint8_t t;
        if (p >= n) return;
        t = cls[p]; cp_tag[i] = t;
        switch (t) {
        case 1: if (p + 3 > n || p + 3 + be16(cls + p + 1) > n) return; cp_off[i] = p + 3; cp_len[i] = be16(cls + p + 1); p += 3 + cp_len[i]; break;
        case 3: case 4: if (p + 5 > n) return; cp_int[i] = be32(cls + p + 1); p += 5; break;
        case 5: case 6: if (p + 9 > n) return; p += 9; if (i + 1 < cnt) cp_tag[i + 1] = 0; i++; break;
        case 7: case 8: case 16: case 19: case 20: if (p + 3 > n) return; cp_a[i] = be16(cls + p + 1); p += 3; break;
        case 9: case 10: case 11: case 12: case 18: if (p + 5 > n) return; cp_a[i] = be16(cls + p + 1); cp_b[i] = be16(cls + p + 3); p += 5; break;
        case 15: if (p + 4 > n) return; p += 4; break;
        default: return;
        }
    }
    if (p + 8 > n) return;
    this_cls = be16(cls + p + 2);
    q = p + 8 + be16(cls + p + 6) * 2u;                     // after access, this, super, interfaces
    if (q + 2 > n) return;
    for (uint32_t f = be16(cls + q), i = (q += 2, 0); i < f; i++) {    // fields
        uint32_t a;
        if (q + 8 > n) return;
        a = be16(cls + q + 6); q += 8;
        while (a--) { if (q + 6 > n) return; q += 6 + be32(cls + q + 2); if (q > n) return; }
    }
    if (q + 2 > n) return;
    mc = be16(cls + q); q += 2;
    for (uint32_t mi = 0; mi < mc && q + 8 <= n; mi++) {
        uint32_t name = be16(cls + q + 2), desc = be16(cls + q + 4), na = be16(cls + q + 6), param = !(cls[q + 1] & 8);
        q += 8;
        for (uint32_t ai = 0; ai < na; ai++) {
            uint32_t a = q, alen, end, cl;
            const uint8_t *code;
            struct insn hist[10];
            uint32_t nh = 0, in_arr = 0, amask = 0, abad = 0, astart = 0, pc = 0;
            int unrelated, init, kind;
            struct meth *m = 0;
            if (a + 6 > n) return;
            alen = be32(cls + a + 2); end = a + 6 + alen;
            if (end > n) return;
            q = end;
            if (alen <= 11 || !cp_eq(be16(cls + a), "Code")) continue;
            cl = be32(cls + a + 10);
            if (a + 14 + cl > end) return;
            code = cls + a + 14;
            unrelated = 1;                                  // a class that never mentions the region
            if (this_cls && this_cls < cpcount && cp_tag[this_cls] == 7 && cp_has(cp_a[this_cls], "xlet")) unrelated = 0;
            else for (uint32_t i = 1; i < cpcount && unrelated; i++)
                if (cp_tag[i] == 1 && (cp_has(i, "region") || cp_has(i, "wrong region") || cp_has(i, "regioncode"))) unrelated = 0;
            init = cp_eq(name, "<init>");
            kind = desc_kind(desc);
            if (kind) m = meth_get(sighash(this_cls, name, desc), kind);
            while (cl && pc < cl) {
                struct insn in;
                struct insn *prev = nh ? &hist[(nh - 1) % 10] : 0;
                idec(&in, code, cl, pc);
                if (!in.len) break;
                // a constructor filling a field with new int[] { regions }
                if (init && in.op == 0xbc) {
                    if (pc + 1 < cl && code[pc + 1] == 10) { in_arr = 1; amask = 0; abad = 0; astart = pc; }
                } else if (init && in_arr && in.op == 0x4f) {
                    if (nh > 1 && prev->isconst) { if (prev->val - 1 < 7) amask |= prev->val; else abad = 1; }
                    else abad = 1;
                } else if (init && in_arr && in.op == 0xb5) {
                    uint32_t fh = ref_field(in.cpi);
                    in_arr = 0;
                    if (!abad && (amask & 0xff) && pc - astart < 0xa0) {
                        if (fh) {
                            uint32_t i = 0;
                            for (; i < nfld; i++) if (flds[i].hash == fh) { if (flds[i].val != (uint8_t)amask) flds[i].conflict = 1; break; }
                            if (i == nfld && nfld < MAX_FLD) { flds[nfld].hash = fh; flds[nfld].val = (uint8_t)amask; flds[nfld].conflict = 0; nfld++; }
                        }
                        abad = 0;
                    }
                }
                // calls from the three kinds of method
                if (m && (in.op == 0xb6 || in.op == 0xb8 || in.op == 0xb9)) {
                    uint32_t sig = ref_sig(in.cpi), rk = ref_kind(in.cpi);
                    if (kind == K_READ && rk == K_READ && prev && prev->local == param) {
                        uint32_t c, nm, ds;
                        if (sig) add_callee(m, 0, sig);
                        if (ref_parts(in.cpi, &c, &nm, &ds) && c && c < cpcount && cp_tag[c] == 7) {
                            uint32_t u = cp_a[c];
                            if (utf_ok(u) && cp_len[u] == 32 && mem_ci(cls + cp_off[u], 32, "org/bluray/system/RegisterAccess")
                                && cp_eq(nm, "getPSR") && cp_eq(ds, "(I)I")) m->direct = 1;
                        }
                    }
                    if (kind == K_REGION && rk == K_READ && prev && prev->isconst && prev->val == 20 && sig) add_callee(m, 1, sig);
                }
                // a region check called with a constant or a field, followed by ifeq / ifne
                if (!unrelated && (in.op == 0xb6 || in.op == 0xb8 || in.op == 0xb9) && ref_kind(in.cpi) == K_CHECK) {
                    uint32_t nx = pc + in.len, sig = ref_sig(in.cpi);
                    if (nx < cl && (code[nx] == 0x99 || code[nx] == 0x9a) && prev) {
                        if (!prev->isconst || prev->val - 1 > 6) {
                            if (prev->op == 0x2e) {                 // ... getfield/getstatic, index, iaload
                                uint32_t back = nh < 8 ? (nh < 2 ? 1 : nh) : 8;
                                for (uint32_t k = 0; k < back; k++) {
                                    struct insn *h = &hist[(nh - 1 - k) % 10];
                                    if (h->op == 0xb2 || h->op == 0xb4) {
                                        uint32_t fh = ref_field(h->cpi);
                                        if (fh && sig && ncall < MAX_CALL) { calls[ncall].sig = sig; calls[ncall].field = fh; calls[ncall].kind = 1; calls[ncall].val = 0; ncall++; }
                                        break;
                                    }
                                }
                            }
                        } else if (sig && ncall < MAX_CALL) {
                            calls[ncall].sig = sig; calls[ncall].field = 0; calls[ncall].kind = 2; calls[ncall].val = (uint16_t)prev->val; ncall++;
                        }
                    }
                }
                hist[nh % 10] = in; nh++;
                pc += in.len;
            }
            // a (I)Z method: is it "return (r & regionMethod()) != 0" for one of the ()I methods it calls?
            if (kind == K_CHECK && m && cl) {
                for (uint32_t pc2 = 0; pc2 < cl;) {
                    struct insn in;
                    idec(&in, code, cl, pc2);
                    if (!in.len) break;
                    if ((in.op == 0xb8 || in.op == 0xb6) && ref_kind(in.cpi) == K_REGION) {
                        uint32_t s = ref_sig(in.cpi);
                        if (s && is_check(code, cl, param, in.cpi)) add_callee(m, 2, s);
                    }
                    pc2 += in.len;
                }
            }
        }
    }
}

// ---- the .jar files ------------------------------------------------------------------------------------------------
static int endswith(const char *a, size_t la, const char *b)
{
    size_t lb = strlen(b);
    return la >= lb && !memcmp(a + la - lb, b, lb);
}
static void do_jar(const char *path)
{
    int fd = open(path, O_RDONLY);
    struct stat st;
    uint32_t m, p, cur, ent = 0, found = 0;
    ssize_t r;
    if (fd < 0) return;
    if (fstat(fd, &st) || st.st_size <= 0 || st.st_size > (off_t)JAR_MAX) { close(fd); return; }
    jlen = 0;
    while (jlen < (uint32_t)st.st_size && (r = read(fd, jar + jlen, (uint32_t)st.st_size - jlen)) > 0) jlen += (uint32_t)r;
    close(fd);
    if (jlen != (uint32_t)st.st_size || jlen <= 0x15) return;
    m = jlen < 0x10015 ? jlen : 0x10015;
    for (p = jlen - 22; p + m >= jlen + 1 && p + 4 <= jlen; p--) {
        if (le32(jar + p) == 0x06054b50) { found = 1; break; }
        if (!p) break;
    }
    if (!found || le32(jar + p + 16) >= jlen || !(ent = le16(jar + p + 10))) return;
    cur = le32(jar + p + 16);
    for (uint32_t i = 0; i < ent; i++) {
        const uint8_t *h = jar + cur;
        uint32_t nl, nx, us, cs, lho, meth, d;
        if (cur + 46 > jlen || le32(h) != 0x02014b50) break;
        nl = le16(h + 28);
        nx = cur + 46 + nl + le16(h + 30) + le16(h + 32);
        if (nx > jlen) break;
        meth = le16(h + 10); cs = le32(h + 20); us = le32(h + 24); lho = le32(h + 42);
        cur = nx;
        if (nl <= 5 || !endswith((const char *)h + 46, nl, ".class") || us - 1 >= CLS_MAX) continue;
        if (lho + 30 > jlen || le32(jar + lho) != 0x04034b50) continue;
        d = lho + 30 + le16(jar + lho + 26) + le16(jar + lho + 28);
        if (d + cs > jlen) continue;
        if (meth == 0) { if (cs != us) continue; memcpy(cls, jar + d, cs); clen = cs; }
        else if (meth == 8) {
            struct zin z = { jar + d, cs, 0, 0, cls, 0, CLS_MAX };
            if (!inflate(&z) || z.len != us) continue;
            clen = z.len;
        } else continue;
        do_class();
    }
}

static struct meth *meth_find(uint32_t h)
{
    for (uint32_t i = 0; i < nmeth; i++) if (meths[i].hash == h) return &meths[i];
    return 0;
}

int main(int argc, char **argv)
{
    char dir[1024], path[2048];
    const char *slash;
    DIR *d;
    struct dirent *de;
    uint32_t cmask = 0, fval = 0;
    int haveconst = 0, havefield = 0, changed;
    if (argc < 2) { fputs("usage: bdcallgraph <.../BDMV/MovieObject.bdmv>\n", stderr); return 2; }
    if (!(slash = strrchr(argv[1], '/')) || (size_t)(slash - argv[1]) + 1 >= 1024) { puts("UNKNOWN"); return 1; }
    snprintf(dir, sizeof dir, "%.*s/JAR", (int)(slash - argv[1]), argv[1]);
    if ((d = opendir(dir))) {
        while ((de = readdir(d))) {
            size_t l = strlen(de->d_name);
            if (l <= 3 || !endswith(de->d_name, l, ".jar")) continue;
            snprintf(path, sizeof path, "%s/%s", dir, de->d_name);
            do_jar(path);
        }
        closedir(d);
    }
    // which methods read a PSR, return the region, check a region
    for (uint32_t i = 0; i < nmeth; i++) if (meths[i].direct) meths[i].reads = 1;
    do {
        changed = 0;
        for (uint32_t i = 0; i < nmeth; i++) {
            struct meth *m = &meths[i];
            if (m->reads || m->kind != K_READ) continue;
            for (uint32_t k = 0; k < m->n[0]; k++) { struct meth *c = meth_find(m->callee[0][k]); if (c && c->reads) { m->reads = 1; changed = 1; break; } }
        }
    } while (changed);
    for (uint32_t i = 0; i < nmeth; i++) {
        struct meth *m = &meths[i];
        if (m->kind == K_REGION) for (uint32_t k = 0; k < m->n[1]; k++) { struct meth *c = meth_find(m->callee[1][k]); if (c && c->reads) { m->region = 1; break; } }
    }
    for (uint32_t i = 0; i < nmeth; i++) {
        struct meth *m = &meths[i];
        if (m->kind == K_CHECK) for (uint32_t k = 0; k < m->n[2]; k++) { struct meth *c = meth_find(m->callee[2][k]); if (c && c->region) { m->check = 1; break; } }
    }
    // what the disc passes to its region checks
    for (uint32_t i = 0; i < ncall; i++) {
        struct meth *m = meth_find(calls[i].sig);
        if (!m || !m->check) continue;
        if (calls[i].kind == 2) { if ((uint16_t)(calls[i].val - 1) < 7) { cmask |= calls[i].val; haveconst = 1; } }
        else if (calls[i].kind == 1) {
            for (uint32_t k = 0; k < nfld; k++) if (flds[k].hash == calls[i].field) {
                if (flds[k].conflict) { puts("UNKNOWN"); return 1; }
                if (flds[k].val) { if (havefield && fval != flds[k].val) { puts("UNKNOWN"); return 1; } fval = flds[k].val; havefield = 1; }
                break;
            }
        }
    }
    if (!haveconst) cmask = 0;
    if (!havefield) fval = cmask;
    if ((fval & 0xff) - 1 < 7) { printf("%u\n", fval & 0xff); return 0; }
    puts("UNKNOWN");
    return 1;
}
