// oppo-dv-mkv: several external subtitles for disc images and Blu-ray folders, like Emby / Jellyfin / Plex:
//   Title.iso + Title.srt, Title.en.srt, Title.pt.srt, Title.eng.forced.srt, Title.pt-BR.ass ...
// each its own entry in the player's subtitle menu, named by its language ("English", "Portuguese (Forced)" ...;
// a file without a language keeps the player's own name "Other").
// RU 65-0131 player program. The player's disc module (playback_disc_extern_subtitle.c) knows ONE file: at disc start
// FUN_0093f464(path) turns Title.iso into Title.srt (.ssa .ass .smi) and keeps the path at 0x134d2e0+0x4d4 (type at
// +0x4d0); every subtitle list then adds one entry after the disc's own streams, and choosing it starts the parse
// thread on that path. Here: es_setpath replaces FUN_0093f464 (finds all matching files, the first one goes to
// +0x4d4 exactly as before) and the stubs in multi.S make the lists add N entries instead of one, name them, and
// point +0x4d4 at the chosen file before the parse thread starts. Loaded at 0x1b90000 (a RWX region extsub.sh maps).
typedef unsigned u32; typedef unsigned short u16; typedef unsigned char u8;

#define MAXF 10                     // files kept (bare name first, then by name)
#define NAMEMAX 160
#define PATHMAX 0x400

// player program: disc external-subtitle state, UI strings
#define ES_PATH (*(char **)0x134d7b4)            // 0x134d2e0 + 0x4d4: file the parse thread opens
#define ES_TYPE (*(volatile u32 *)0x134d7b0)     // + 0x4d0: 1 srt, 2 ass, 3 ssa, 4 smi (5 sup)
#define STR ((u16 **)0x1a55cd4)                  // UI string table (UTF-16), index * 12 + UI language
#define UILANG (*(volatile u8 *)0x134ca00)
#define STR_OTHER 0x3090
#define LANGTAB ((const u8 *)0x1252068)          // 485 x 10 B: +2 u16 name index, +4 ISO 639-2, +7 ISO 639-1
#define NLANG 485
// player functions: c_* are ARM, FUN_* Thumb, libc through its PLT (ARM)
#define c_mem_alloc ((void *(*)(u32))0x475de8)
#define c_mem_free ((void (*)(void *))0x475e1c)
#define lang2 ((int (*)(const char *, u16 *))0xac7b49)   // ISO 639-1 -> name index
#define lang3 ((int (*)(const char *, u16 *))0xac7b89)   // ISO 639-2 (B and T codes) -> name index
#define p_opendir ((void *(*)(const char *))0x300a4)
#define p_readdir ((u8 *(*)(void *))0x316ec)             // struct dirent (32-bit): d_name at +11
#define p_closedir ((int (*)(void *))0x30aa8)
#define pb_clear_ext ((void (*)(void))0x93f105)          // FUN_0093f104: hides the file subtitle, "active" byte 0
#define ACTIVE (*(volatile u8 *)0x1970137)

struct file { char name[NAMEMAX]; u8 type, bare; u16 lang; char extra[34]; u16 label[64]; };
struct st {
    u32 magic, version;
    void (*setpath)(const char *);
    u32 stub[8];                    // multi.S stubs t1..t8 (Thumb addresses) for extsub.sh
    volatile u32 n, k;              // files of the current disc, the one at +0x4d4
    char *volatile ptr;             // what we put at +0x4d4 (another value there: the player's own single entry)
    volatile u32 calls, scans, switches, names;
    char dir[PATHMAX];              // folder of the disc, with '/'
    struct file f[MAXF];
};
extern void t1(void), t2(void), t3(void), t4(void), t5(void), t6(void), t7(void), t8(void);
void es_setpath(const char *iso);
__attribute__((section(".hdr"), used)) struct st es = { 0x534d5845, 1, es_setpath,
    { (u32)t1, (u32)t2, (u32)t3, (u32)t4, (u32)t5, (u32)t6, (u32)t7, (u32)t8 } };

void *memcpy(void *d, const void *s, u32 n) { u8 *a = d; const u8 *b = s; while (n--) *a++ = *b++; return d; }
void *memset(void *d, int c, u32 n) { u8 *a = d; while (n--) *a++ = c; return d; }
void __aeabi_memcpy(void *d, const void *s, u32 n) { memcpy(d, s, n); }   // struct copies
static u32 slen(const char *s) { u32 n = 0; while (s[n]) n++; return n; }
static u8 low(u8 c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }
static int ieq(const char *a, const char *b, u32 n) { while (n--) { if (low(*a) != low(*b)) return 0; a++; b++; } return 1; }
static int alpha(const char *s, u32 n) { while (n--) { u8 c = low(*s++); if (c < 'a' || c > 'z') return 0; } return 1; }
static int cmpname(const char *a, const char *b) { while (*a && low(*a) == low(*b)) { a++; b++; } return low(*a) - low(*b); }

static int ours(void) { return es.n && ES_PATH && ES_PATH == es.ptr; }
u32 es_n(void) { return ours() ? es.n : 1; }
static u32 es_k(void) { return ours() ? es.k : 0; }

static int typeof_ext(const char *e)    // after the last '.'
{
    if (ieq(e, "srt", 4)) return 1;
    if (ieq(e, "ass", 4)) return 2;
    if (ieq(e, "ssa", 4)) return 3;
    if (ieq(e, "smi", 4)) return 4;
    return 0;
}

// one token of the name between the title and the extension: a language (en, eng, pt-BR, English) or a mark
static int langtok(struct file *f, const char *t, u32 n)
{
    char c[4]; u16 ix;
    u32 m = n;
    for (u32 i = 0; i < n; i++) if (t[i] == '-' || t[i] == '_') { m = i; break; }   // pt-BR, en_US: the language part
    if ((m == 2 || m == 3) && alpha(t, m)) {
        c[0] = low(t[0]); c[1] = low(t[1]); c[2] = m == 3 ? low(t[2]) : 0; c[3] = 0;
        if ((m == 2 ? lang2(c, &ix) : lang3(c, &ix)) == 0) {
            f->lang = ix;
            if (m < n) { u32 e = slen(f->extra); char *x = f->extra + e;       // keep the region: "Portuguese (BR)"
                for (u32 i = m + 1; i < n && e < sizeof f->extra - 2; i++, e++) *x++ = t[i] >= 'a' && t[i] <= 'z' ? t[i] - 32 : t[i];
                *x = 0; }
            return 1;
        }
    }
    if (n >= 4 && alpha(t, n))                          // a language written out, as the English UI names it
        for (u32 i = 0; i < NLANG; i++) {
            u16 nx = *(const u16 *)(LANGTAB + i * 10 + 2), *w = STR[nx * 12];
            u32 j = 0;
            if (!w) continue;
            while (j < n && w[j] < 128 && low((u8)w[j]) == low(t[j])) j++;
            if (j == n && !w[j]) { f->lang = nx; return 1; }
        }
    return 0;
}

static void addextra(struct file *f, const char *t, u32 n)
{
    static const char *const marks[][2] = { { "forced", "Forced" }, { "sdh", "SDH" }, { "cc", "CC" }, { "hi", "SDH" },
                                            { "default", "" }, { "full", "" } };
    const char *s = t; u32 sn = n;
    for (u32 i = 0; i < sizeof marks / sizeof marks[0]; i++)
        if (slen(marks[i][0]) == n && ieq(t, marks[i][0], n)) { s = marks[i][1]; sn = slen(s); break; }
    if (!sn) return;
    u32 e = slen(f->extra);
    if (e + sn + 3 > sizeof f->extra) return;
    if (e) { f->extra[e++] = ','; f->extra[e++] = ' '; }
    for (u32 i = 0; i < sn; i++) f->extra[e++] = s[i];
    f->extra[e] = 0;
}

static void parse(struct file *f, const char *mid, u32 n)   // mid: ".en.forced" (empty for the bare name)
{
    f->lang = 0xffff; f->extra[0] = 0; f->bare = n == 0;
    while (n) {
        while (n && (*mid == '.' || *mid == ' ')) { mid++; n--; }
        u32 t = 0; while (t < n && mid[t] != '.') t++;
        if (t && !(f->lang == 0xffff && langtok(f, mid, t))) addextra(f, mid, t);
        mid += t; n -= t;
    }
}

static const u16 *label(u32 j)          // name in the list: language (or "Other") + " (marks)"
{
    if (!ours()) return STR[STR_OTHER + UILANG];
    if (j >= es.n) j = es.n - 1;
    struct file *f = &es.f[j];
    const u16 *w = f->lang != 0xffff ? STR[f->lang * 12 + UILANG] : 0;
    if (!w) w = STR[STR_OTHER + UILANG];
    u32 o = 0;
    if (w) while (*w && o < 40) f->label[o++] = *w++;
    if (f->extra[0]) {
        const char *x = f->extra;
        f->label[o++] = ' '; f->label[o++] = '(';
        while (*x && o < 61) f->label[o++] = (u8)*x++;
        f->label[o++] = ')';
    }
    u32 same = 0;                                          // two files with the same name: "English 2"
    for (u32 i = 0; i < j; i++) if (es.f[i].lang == f->lang && !cmpname(es.f[i].extra, f->extra)) same++;
    if (same && o < 61) { f->label[o++] = ' '; f->label[o++] = '1' + same; }
    f->label[o] = 0;
    es.names++;
    return f->label;
}

static char *dup(u32 j)                 // c_mem_alloc'ed full path of file j (+0x4d4 is freed by the player)
{
    u32 a = slen(es.dir), b = slen(es.f[j].name);
    char *p = c_mem_alloc(a + b + 1);
    if (!p) return 0;
    for (u32 i = 0; i < a; i++) p[i] = es.dir[i];
    for (u32 i = 0; i <= b; i++) p[a + i] = es.f[j].name[i];
    return p;
}

// FUN_0093f464 replaced (jumped to from its first instruction; returns to its caller)
void es_setpath(const char *iso)
{
    es.calls++;
    if (!iso) return;
    ES_PATH = 0; es.n = 0; es.k = 0; es.ptr = 0;
    u32 L = slen(iso);
    if (L >= PATHMAX - 1) return;
    for (u32 i = 0; i <= L; i++) es.dir[i] = iso[i];
    if (L > 4 && es.dir[L - 4] == '.' && ieq(es.dir + L - 3, "iso", 3)) es.dir[L -= 4] = 0;
    while (L > 1 && es.dir[L - 1] == '/') es.dir[--L] = 0;      // a Blu-ray folder: Title/ -> Title.srt next to it
    u32 s = L; while (s && es.dir[s - 1] != '/') s--;
    if (!s) return;
    char title[NAMEMAX]; u32 tl = L - s;
    if (tl >= NAMEMAX - 8) return;
    for (u32 i = 0; i <= tl; i++) title[i] = es.dir[s + i];
    es.dir[s] = 0;                                              // "folder/"
    es.dir[s - 1] = 0; void *d = p_opendir(s > 1 ? es.dir : "/"); es.dir[s - 1] = '/';
    if (!d) return;
    u32 n = 0; u8 *e;
    es.scans++;
    while ((e = p_readdir(d))) {
        const char *nm = (const char *)e + 11; u32 nl = slen(nm);
        if (nl < tl + 4 || nl >= NAMEMAX || !ieq(nm, title, tl) || nm[tl] != '.') continue;
        u32 x = nl; while (nm[x - 1] != '.') x--;               // extension after the last '.'
        int ty = typeof_ext(nm + x);
        if (!ty) continue;
        struct file f;
        for (u32 i = 0; i <= nl; i++) f.name[i] = nm[i];
        f.type = ty;
        parse(&f, nm + tl, x - 1 - tl);
        // keep sorted: bare name first (srt, ssa, ass, smi as the player chose), then by name
        u32 at = n;
        while (at > 0) {
            struct file *p = &es.f[at - 1];
            int before = f.bare != p->bare ? f.bare : f.bare ? ((f.type == 1 ? 0 : f.type == 3 ? 1 : f.type) < (p->type == 1 ? 0 : p->type == 3 ? 1 : p->type))
                                                             : cmpname(f.name, p->name) < 0;
            if (!before) break;
            at--;
        }
        if (at >= MAXF) continue;
        for (u32 i = (n < MAXF ? n : MAXF - 1); i > at; i--) es.f[i] = es.f[i - 1];
        es.f[at] = f;
        if (n < MAXF) n++;
    }
    p_closedir(d);
    if (!n) return;
    char *p = dup(0);
    if (!p) return;
    es.k = 0; es.n = n; es.ptr = p;
    ES_TYPE = es.f[0].type;
    ES_PATH = p;
}

// stubs (multi.S). D = the disc's own subtitle streams, N = files, K = file at +0x4d4. Lists: 0 Off, 1..D disc,
// D+1..D+N files.
void es_t1(u32 d, u32 act, u32 *sp) { sp[4] = d + es_n(); if (act) sp[5] = d + 1 + es_k(); }   // popup: count, current
u32 es_t2(u32 d, u32 act, u32 *sp, u32 cur) { sp[6] = d + es_n(); return act ? d + 1 + es_k() : cur; }
u32 es_t3(u32 d) { return d + es_n(); }                                                         // name: total
const u16 *es_t4(u32 idx, u32 total)                                                            // name of a file entry
{
    u32 n = es_n();
    return idx + n > total && idx <= total ? label(idx + n - total - 1) : 0;
}
void es_t5(u32 cnt, u8 *sp) { *(u32 *)(sp + 0x28) = cnt - es_n() + es_k(); }                   // select: current
u32 es_t6(u32 sel, u32 cnt)                                                                     // select: a file?
{
    u32 n = es_n();
    if (sel + n < cnt || sel >= cnt) return 0;
    u32 j = sel + n - cnt;
    if (ours() && j != es.k) {
        if (ACTIVE) pb_clear_ext();     // another file while one is shown: off first, as the player does for a disc stream
        char *p = dup(j), *o = ES_PATH;
        if (p) { es.ptr = p; es.k = j; ES_TYPE = es.f[j].type; ES_PATH = p; c_mem_free(o); es.switches++; }
    }
    return 1;
}
const u16 *es_t7(void) { return label(es_k()); }                                                // info banner
