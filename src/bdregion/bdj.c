// bdregion, BD-J part: the region of a BD-J disc from its JAR folder (BDMV/JAR), without running it.
// Included by detect.c. Written for oppo-dv-mkv after the logic of autoABC's region_fast by DamnFine815 (MIT);
// no code copied. Two stages, the first that knows decides:
//  1. config files in the unpacked JAR folders (BDMV/JAR/<name>/): fp_config.txt, playbackconfig.xml,
//     projectsettings.xml, settings.xml, startup.properties, bdlive.properties (config_mask below)
//  2. each .jar (zip): the same config files inside it, else every class with a ()Z method whose name says it checks
//     the region (checkregion, isregioncode, regionallowed, ...; not wrong/lockout/invalid/blocked), or any ()Z method
//     when the class mentions checkregioncode/regioncheck: the method is run three times in a small JVM with
//     RegisterAccess.getInstance().getPSR(20) = 1, 2, 4; the runs that return true are the allowed regions.
// Results: a region mask (1 A, 2 B, 4 C, combinations), 7 region free, 0 unknown. Disagreeing sources -> unknown.
#include <dirent.h>

#define FREE 7
static const char *const CFG[6] = { "fp_config.txt", "playbackconfig.xml", "projectsettings.xml", "settings.xml",
                                     "startup.properties", "bdlive.properties" };

static int endswith(const char *s, const char *t)
{
    size_t a = strlen(s), b = strlen(t);
    return b <= a && !memcmp(s + a - b, t, b);
}

// ---- config text -----------------------------------------------------------------------------------------------------
// first occurrence of key; after it spaces, tabs, line ends, quotes, ':', '=', '>' may follow, then a number
static int num_after(const uint8_t *t, uint32_t n, const char *key, uint32_t *val)
{
    size_t k = strlen(key);
    *val = 0;
    for (uint32_t i = 0; i + k < n; i++) {
        uint32_t j = i + (uint32_t)k, v = 0;
        if (memcmp(t + i, key, k)) continue;
        for (; j < n; j++) {
            uint8_t c = t[j];
            if (c == '=' || c == '>' || (c >= 9 && c <= 0x27 && (0x42800011u >> (c - 9) & 1))) continue;
            if (c >= '0' && c <= '9') {
                *val = 1;
                for (; j < n && t[j] >= '0' && t[j] <= '9'; j++) v = v * 10 + (t[j] - '0');
                return (int)v;
            }
            break;
        }
        return 0;
    }
    return 0;
}
static int contains_ci(const uint8_t *t, uint32_t n, const char *s)
{
    size_t k = strlen(s);
    if (!k || k > n) return 0;
    for (uint32_t i = 0; i + k <= n; i++) {
        size_t j = 0;
        while (j < k) {
            uint8_t a = t[i + j], b = (uint8_t)s[j];
            if (a >= 'A' && a <= 'Z') a |= 0x20;
            if (b >= 'A' && b <= 'Z') b |= 0x20;
            if (a != b) break;
            j++;
        }
        if (j == k) return 1;
    }
    return 0;
}
// the region letters/digits after key (exact match), up to '<' or the line end, within 48 characters
static uint32_t region_list(const uint8_t *t, uint32_t n, const char *key)
{
    size_t k = strlen(key);
    uint32_t m = 0, i, end;
    for (i = 0;; i++) { if (i + k >= n) return 0; if (!memcmp(t + i, key, k)) break; }
    i += (uint32_t)k; end = i + 0x30 < n ? i + 0x30 : n;
    for (; i < end; i++) {
        uint8_t c = t[i];
        if (c == '<' || c == '\n' || c == '\r') break;
        if (c == 'A' || c == 'a' || c == '1') m |= 1;
        else if (c == 'B' || c == 'b' || c == '2') m |= 2;
        else if (c == 'C' || c == 'c' || c == '4') m |= 4;
    }
    return m;
}
static uint32_t config_mask(const uint8_t *t, uint32_t n, const char *name)
{
    uint32_t f, g, r, c, m;
    if (!t || !n) return 0;
    r = (uint32_t)num_after(t, n, "RegionCheckRequired", &f); c = (uint32_t)num_after(t, n, "RegionCodeToCheckFor", &g);
    if (f) { if (r == 0) return FREE; if (r == 1 && g && c >= 1 && c <= 7) return c; }
    r = (uint32_t)num_after(t, n, "REGION_CHECK_REQUIRED", &f); c = (uint32_t)num_after(t, n, "REGION_TO_CHECK_FOR", &g);
    if (f) { if (r == 0) return FREE; if (r == 1 && g && c >= 1 && c <= 7) return c; }
    r = (uint32_t)num_after(t, n, "region.free", &f);
    if (f && r == 1) return FREE;
    if (contains_ci(t, n, "disc.regions=") && (m = region_list(t, n, "disc.regions="))) return m;
    if (name && endswith(name, "settings.xml") && contains_ci(t, n, "<region>")) return region_list(t, n, "<region>");
    return 0;
}

#include "inflate.h"

// ---- zip ---------------------------------------------------------------------------------------------------------
#define JAR_MAX  (4u << 20)
#define ENT_MAX  0x80000
static uint8_t jar[JAR_MAX], ent[ENT_MAX];
static uint32_t jlen;
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static int zip_entry(uint32_t lho, uint32_t method, uint32_t csize, uint32_t usize, uint32_t *out)
{
    uint32_t d;
    if (lho + 30 > jlen || le32(jar + lho) != 0x04034b50) return 0;
    d = lho + 30 + le16(jar + lho + 26) + le16(jar + lho + 28);
    if (d + csize > jlen) return 0;
    if (method == 8) {
        struct zin z = { jar + d, csize, 0, 0, ent, 0, ENT_MAX };
        if (!inflate(&z)) return 0;
        *out = z.len;
        return 1;
    }
    if (method != 0 || csize != usize) return 0;
    memcpy(ent, jar + d, csize);
    *out = csize;
    return 1;
}
struct cdir { uint32_t pos, end; };
static int zip_open(struct cdir *cd)
{
    uint32_t k = jlen < 0x101d0 ? jlen : 0x101d0;
    for (uint32_t p = jlen - 22; k > 0x15; k--, p--) {
        if (le32(jar + p) != 0x06054b50) continue;
        cd->pos = le32(jar + p + 16); cd->end = cd->pos + le32(jar + p + 12);
        return cd->end <= jlen && cd->end >= cd->pos;
    }
    return 0;
}
struct zent { char name[256]; uint32_t method, csize, usize, lho; };
static int zip_next(struct cdir *cd, struct zent *e)
{
    const uint8_t *h = jar + cd->pos;
    uint32_t nl, nx;
    if (cd->pos + 46 > cd->end || le32(h) != 0x02014b50) return 0;
    nl = le16(h + 28);
    nx = cd->pos + 46 + nl + le16(h + 30) + le16(h + 32);
    if (nx > cd->end) return 0;
    e->method = le16(h + 10); e->csize = le32(h + 20); e->usize = le32(h + 24); e->lho = le32(h + 42);
    if (nl > 255) nl = 255;
    memcpy(e->name, h + 46, nl); e->name[nl] = 0;
    cd->pos = nx;
    return 1;
}

// ---- class files and the small JVM -------------------------------------------------------------------------------
#define CP_MAX 0x1000
static uint8_t cp_tag[CP_MAX];
static uint16_t cp_a[CP_MAX], cp_b[CP_MAX];
static uint32_t cp_off[CP_MAX], cp_int[CP_MAX];
static uint32_t clen;
static uint16_t be16b(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static int cp_eq(uint32_t i, const char *s)
{
    size_t k = strlen(s);
    return i >= 1 && i < CP_MAX && cp_tag[i] == 1 && cp_a[i] == k && !memcmp(ent + cp_off[i], s, k);
}
static int cp_has(uint32_t i, const char *s)
{
    return i >= 1 && i < CP_MAX && cp_tag[i] == 1 && contains_ci(ent + cp_off[i], cp_a[i], s);
}
struct jv { uint32_t known, v; };
// run a ()Z method's code with getPSR(20) = psr; 1 and *res if it returned a known value
static int run_bool(const uint8_t *code, uint32_t n, uint32_t getpsr, uint32_t getinst, uint32_t psr, uint32_t *res)
{
    struct jv st[64], loc[64];
    uint32_t sp = 0, pc = 0;
    memset(loc, 0, sizeof loc);
    for (int steps = 0; pc < n && steps < 2000; steps++) {
        uint8_t op = code[pc];
        uint32_t nx = pc + 1;
        if (op == 0) { pc = nx; continue; }
        if (op >= 2 && op <= 8) { if (sp >= 64) return 0; st[sp].known = 1; st[sp++].v = (uint32_t)(op - 3); pc = nx; continue; }
        if (op == 0x10) { if (nx >= n || sp >= 64) return 0; st[sp].known = 1; st[sp++].v = (uint32_t)(int8_t)code[nx]; pc += 2; continue; }
        if (op == 0x11) { if (pc + 3 > n || sp >= 64) return 0; st[sp].known = 1; st[sp++].v = (uint32_t)(int16_t)be16b(code + nx); pc += 3; continue; }
        if (op == 0x12 || op == 0x13) {
            uint32_t i;
            if (op == 0x12) { if (nx >= n) return 0; i = code[nx]; pc += 2; }
            else { if (pc + 3 > n || code[nx] > 0x0f) return 0; i = be16b(code + nx); pc += 3; }
            if (cp_tag[i] != 3 || sp >= 64) return 0;
            st[sp].known = 1; st[sp++].v = cp_int[i];
            continue;
        }
        if (op == 0x15) { uint32_t i; if (nx >= n) return 0; i = code[nx]; if (i >= 64 || sp >= 64) return 0; st[sp++] = loc[i]; pc += 2; continue; }
        if (op >= 0x1a && op <= 0x1d) { if (sp >= 64) return 0; st[sp++] = loc[op - 0x1a]; pc = nx; continue; }
        if (op == 0x36) { uint32_t i; if (nx >= n || !sp || (i = code[nx]) >= 64) return 0; loc[i] = st[--sp]; pc += 2; continue; }
        if (op >= 0x3b && op <= 0x3e) { if (!sp) return 0; loc[op - 0x3b] = st[--sp]; pc = nx; continue; }
        if (op == 0x57) { if (!sp) return 0; sp--; pc = nx; continue; }
        if (op == 0x59) { if (!sp || sp >= 64) return 0; st[sp] = st[sp - 1]; sp++; pc = nx; continue; }
        if (op == 0x60 || op == 0x64 || op == 0x68 || (op >= 0x78 && op <= 0x82 && !(op & 1))) {
            uint32_t a, b, r;
            if (sp < 2 || !st[sp - 2].known || !st[sp - 1].known) return 0;
            a = st[sp - 2].v; b = st[sp - 1].v;
            switch (op) {
            case 0x60: r = a + b; break;
            case 0x64: r = a - b; break;
            case 0x68: r = a * b; break;
            case 0x78: r = a << (b & 31); break;
            case 0x7a: r = (uint32_t)((int32_t)a >> (b & 31)); break;
            case 0x7e: r = a & b; break;
            case 0x80: r = a | b; break;
            case 0x82: r = a ^ b; break;
            default: r = a >> (b & 31);                     // iushr
            }
            sp--; st[sp - 1].known = 1; st[sp - 1].v = r; pc = nx;
            continue;
        }
        if (op >= 0x99 && op <= 0x9e) {                     // if<cond> on one value
            int32_t v; int t;
            if (pc + 3 > n || !sp) return 0;
            sp--;
            if (!st[sp].known) return 0;
            v = (int32_t)st[sp].v;
            t = op == 0x99 ? v == 0 : op == 0x9a ? v != 0 : op == 0x9b ? v < 0 : op == 0x9c ? v >= 0 : op == 0x9d ? v > 0 : v <= 0;
            pc = t ? pc + (uint32_t)(int16_t)be16b(code + nx) : pc + 3;
            continue;
        }
        if (op >= 0x9f && op <= 0xa4) {                     // if_icmp<cond>
            int32_t a, b; int t;
            if (pc + 3 > n || sp < 2) return 0;
            sp -= 2;
            if (!st[sp].known || !st[sp + 1].known) return 0;
            a = (int32_t)st[sp].v; b = (int32_t)st[sp + 1].v;
            t = op == 0x9f ? a == b : op == 0xa0 ? a != b : op == 0xa1 ? a < b : op == 0xa2 ? a >= b : op == 0xa3 ? a > b : a <= b;
            pc = t ? pc + (uint32_t)(int16_t)be16b(code + nx) : pc + 3;
            continue;
        }
        if (op == 0xa7) { if (pc + 3 > n) return 0; pc += (uint32_t)(int16_t)be16b(code + nx); continue; }
        if (op == 0xaa || op == 0xab) {                     // tableswitch / lookupswitch
            uint32_t p = nx + ((3 - pc) & 3), key, def, t;
            if (!sp || !st[sp - 1].known) return 0;
            key = st[--sp].v;
            if (op == 0xaa) {
                uint32_t lo, hi;
                if (p + 12 > n) return 0;
                def = be32(code + p); lo = be32(code + p + 4); hi = be32(code + p + 8);
                if (hi < lo || p + (hi - lo) * 4 + 16 > n) return 0;
                t = key >= lo && key <= hi ? be32(code + p + 12 + (key - lo) * 4) : def;
            } else {
                uint32_t np;
                if (p + 8 > n) return 0;
                def = be32(code + p); np = be32(code + p + 4);
                if (p + 8 + np * 8 > n) return 0;
                t = def;
                for (uint32_t i = 0; i < np; i++) if (be32(code + p + 8 + i * 8) == key) { t = be32(code + p + 12 + i * 8); break; }
            }
            pc += t;
            continue;
        }
        if (op == 0xac) {                                   // ireturn
            if (!sp || !st[sp - 1].known) return 0;
            *res = st[sp - 1].v != 0;
            return 1;
        }
        if (op == 0xb6 || op == 0xb8 || op == 0xb9) {       // invokevirtual / invokestatic / invokeinterface
            uint32_t i;
            if (pc + 3 > n || (op == 0xb9 && pc + 5 > n)) return 0;
            i = be16b(code + nx);
            if (i == getinst) { if (sp >= 64) return 0; st[sp].known = 1; st[sp++].v = 1234; }
            else {
                if (i != getpsr || !sp || !st[sp - 1].known || st[sp - 1].v != 20) return 0;
                sp--;                                       // the argument (20)
                if (op != 0xb8) { if (!sp) return 0; sp--; }    // the RegisterAccess object
                st[sp].known = 1; st[sp++].v = psr;
            }
            pc += op == 0xb9 ? 5 : 3;
            continue;
        }
        return 0;                                           // anything else: not followed
    }
    return 0;
}
// the region mask of one class (0 none/unknown, -1 its methods disagree)
static int class_mask(uint32_t n)
{
    uint32_t cnt, p = 10, getpsr = 0, getinst = 0, flag = 0, m;
    int res = 0;
    clen = n;
    if (n < 10 || be32(ent) != 0xcafebabe || (cnt = be16b(ent + 8)) > CP_MAX) return 0;
    for (uint32_t i = 0; i < cnt; i++) { cp_tag[i] = 0; cp_a[i] = cp_b[i] = 0; cp_off[i] = cp_int[i] = 0; }
    for (uint32_t i = 1; i < cnt; i++) {
        uint8_t t;
        if (p >= n) return 0;
        t = ent[p]; cp_tag[i] = t;
        if (t == 1) { if (p + 3 > n) return 0; cp_a[i] = be16b(ent + p + 1); cp_off[i] = p + 3; p += 3 + cp_a[i]; if (p > n) return 0; }
        else if (t == 3 || t == 4) { if (p + 5 > n) return 0; cp_int[i] = be32(ent + p + 1); p += 5; }
        else if (t == 5 || t == 6) { if (p + 9 > n) return 0; p += 9; i++; }
        else if (t > 20) return 0;
        else if (1u << t & 0x61e00) { if (p + 5 > n) return 0; cp_a[i] = be16b(ent + p + 1); cp_b[i] = be16b(ent + p + 3); p += 5; }
        else if (1u << t & 0x190180) { if (p + 3 > n) return 0; cp_a[i] = be16b(ent + p + 1); p += 3; }
        else if (t == 15) { if (p + 4 > n) return 0; p += 4; }
        else return 0;
    }
    for (uint32_t i = 1; i < cnt; i++) {
        if (cp_tag[i] == 1) { if (cp_has(i, "checkregioncode") || cp_has(i, "regioncheck")) flag = 1; }
        else if ((cp_tag[i] & 0xfe) == 10) {
            uint32_t c = cp_a[i], nt = cp_b[i], cn = 0, nm = 0, ds = 0;
            if (c >= 1 && c < CP_MAX && cp_tag[c] == 7) cn = cp_a[c];
            if (nt >= 1 && nt < CP_MAX && cp_tag[nt] == 12) { nm = cp_a[nt]; ds = cp_b[nt]; }
            if (!cp_eq(cn, "org/bluray/system/RegisterAccess")) continue;
            if (cp_eq(nm, "getPSR") && cp_eq(ds, "(I)I")) getpsr = i;
            if (cp_eq(nm, "getInstance") && cp_eq(ds, "()Lorg/bluray/system/RegisterAccess;")) getinst = i;
        }
    }
    if (!getpsr || p + 8 > n) return 0;
    p += 8 + be16b(ent + p + 6) * 2u;                       // access, this, super, interfaces
    if (p + 2 > n) return 0;
    for (uint32_t f = be16b(ent + p), q = (p += 2, 0); q < f; q++) {   // fields
        uint32_t a;
        if (p + 8 > n) return 0;
        a = be16b(ent + p + 6); p += 8;
        while (a--) { if (p + 6 > n) return 0; p += 6 + be32(ent + p + 2); if (p > n) return 0; }
    }
    if (p + 2 > n) return 0;
    m = be16b(ent + p); p += 2;
    while (m--) {
        uint32_t nm, ds, a;
        if (p + 8 > n) return res;
        nm = be16b(ent + p + 2); ds = be16b(ent + p + 4); a = be16b(ent + p + 6); p += 8;
        while (a--) {
            uint32_t l, e;
            if (p + 6 > n) return res;
            l = be32(ent + p + 2); e = p + 6 + l;
            if (e > n) return res;
            if (cp_eq(ds, "()Z") && l > 11 && cp_eq(be16b(ent + p), "Code") && nm < CP_MAX && cp_tag[nm] == 1
                && !cp_has(nm, "wrong") && !cp_has(nm, "lockout") && !cp_has(nm, "invalid") && !cp_has(nm, "blocked")
                && (cp_has(nm, "checkregion") || cp_has(nm, "regioncheck") || cp_has(nm, "isregioncode")
                    || cp_has(nm, "regionvalid") || cp_has(nm, "validregion") || cp_has(nm, "regionallowed")
                    || cp_has(nm, "allowedregion") || flag)) {
                uint32_t cl = be32(ent + p + 10), r1, r2, r4;
                if (p + 14 + cl <= e && run_bool(ent + p + 14, cl, getpsr, getinst, 1, &r1)
                    && run_bool(ent + p + 14, cl, getpsr, getinst, 2, &r2) && run_bool(ent + p + 14, cl, getpsr, getinst, 4, &r4)) {
                    int mk = (int)(r1 | r2 << 1 | r4 << 2);
                    if (mk && mk != FREE) { if (res && res != mk) return -1; res = mk; }
                }
            }
            p = e;
        }
    }
    return res;
}

// one .jar: its config files, else its classes (0 nothing, FREE, a mask, -1 disagreement)
static int jar_mask(const char *path)
{
    struct cdir cd, c0;
    struct zent e;
    int res = 0, free_ = 0;
    if (!loadfile(path, jar, JAR_MAX, &jlen) || jlen <= 0x15 || !zip_open(&cd)) return 0;
    c0 = cd;
    while (zip_next(&cd, &e)) {
        uint32_t n, m;
        int cfg = 0;
        if (e.usize - 1 >= ENT_MAX) continue;
        for (int i = 0; i < 6; i++) if (endswith(e.name, CFG[i])) cfg = 1;
        if (!cfg || !zip_entry(e.lho, e.method, e.csize, e.usize, &n)) continue;
        m = config_mask(ent, n, e.name);
        if (!m) continue;
        if (m == FREE) { free_ = 1; continue; }
        if (res && res != (int)m) return -1;
        res = (int)m;
    }
    if (res) return res;
    if (free_) return FREE;
    cd = c0;
    while (zip_next(&cd, &e)) {
        uint32_t n;
        int m;
        if (e.usize < 0x40 || e.usize > ENT_MAX || !endswith(e.name, ".class")) continue;
        if (!zip_entry(e.lho, e.method, e.csize, e.usize, &n)) continue;
        m = class_mask(n);
        if (m < 0) continue;                                // its own methods disagree: that class says nothing
        if (!m) continue;
        if (res && res != m) return -1;
        res = m;
    }
    return res;
}

static uint32_t detect_bdj(const char *mobj_path)
{
    static const char suffix[] = "/MovieObject.bdmv";
    char root[0x400], p[0x800];
    size_t len = strlen(mobj_path), sl = sizeof suffix - 1;
    DIR *d;
    struct dirent *de;
    int res = 0, free_ = 0;
    uint8_t buf[0x2000];
    if (len <= sl || strcmp(mobj_path + len - sl, suffix)) return 0;
    len -= sl; if (len > 0x3fb) len = 0x3fb;
    memcpy(root, mobj_path, len); strcpy(root + len, "/JAR");
    if (!(d = opendir(root))) return 0;
    while ((de = readdir(d))) {                             // 1. unpacked JAR folders
        int dres = 0, dfree = 0, bad = 0;
        if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..") || endswith(de->d_name, ".jar")) continue;
        for (int i = 0; i < 6 && !bad; i++) {
            uint32_t n, m;
            snprintf(p, sizeof p, "%s/%s/%s", root, de->d_name, CFG[i]);
            if (!loadfile(p, buf, sizeof buf, &n) || !(m = config_mask(buf, n, CFG[i]))) continue;
            if (m == FREE) dfree = 1;
            else if (dres && dres != (int)m) bad = 1;
            else dres = (int)m;
        }
        if (bad) continue;
        if (dres) { if (res && res != dres) { closedir(d); return 0; } res = dres; }
        else if (dfree) free_ = 1;
    }
    if (res || free_) { closedir(d); return res == FREE ? 0 : (uint32_t)res; }
    rewinddir(d);
    res = 0;
    while ((de = readdir(d))) {                             // 2. the .jar files
        int m;
        if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..") || !endswith(de->d_name, ".jar")) continue;
        snprintf(p, sizeof p, "%s/%s", root, de->d_name);
        m = jar_mask(p);
        if (m <= 0) continue;
        if (m == FREE) { free_ = 1; continue; }
        if (res && res != m) { closedir(d); return 0; }
        res = m;
    }
    closedir(d);
    return (uint32_t)(res == FREE ? 0 : res);
}
