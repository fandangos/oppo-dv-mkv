// oppo-dv-mkv bdregion: Blu-ray region of an HDMV disc from its navigation program (BDMV/MovieObject.bdmv and
// BDMV/index.bdmv). Prints A, B, C or UNKNOWN.
// usage: bdhdmv <path to BDMV/MovieObject.bdmv>
//
// Two region checks that discs do in their First Play movie object are recognised (PSR20 = the player's region,
// 1 A, 2 B, 4 C):
//  1. "NE PSR20, R; JumpTitle W" where title W's object checks again and otherwise plays its warning and loops:
//     "EQ PSR20, R; JumpTitle x; Play...; JumpTitle W"                                     -> the disc is region R
//  2. two forbidden regions, each "EQ PSR20, Ri; JumpTitle W" to the same short warning title (at most 5 commands,
//     a Play then "GoTo 0" as its last), followed within 4 commands by a JumpTitle to another title
//                                                                                          -> the third region
// Anything else (BD-J discs, other layouts) is UNKNOWN: the player's region is then left alone.
// Written for oppo-dv-mkv after the logic of autoABC's region_hdmv_fallback by DamnFine815 (MIT); no code copied.
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define MOBJ_MAX (2u << 20)
#define INDX_MAX (256u << 10)
#define MAX_OBJ  0x800
#define MAX_TTL  0x2000

static uint8_t mobj[MOBJ_MAX], indx[INDX_MAX];
static uint32_t mlen, ilen;
static uint32_t nobj, obj_cmds[MAX_OBJ];   // offset of each object's first command
static uint16_t obj_n[MAX_OBJ];            // its number of commands
static int fp_hdmv, top_hdmv;
static uint16_t fp_obj, top_obj, ntitle;
static uint8_t title_hdmv[MAX_TTL];
static uint16_t title_obj[MAX_TTL];

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }

static int read_all(const char *path, uint8_t *buf, uint32_t max, uint32_t *len)
{
    int fd = open(path, O_RDONLY);
    ssize_t r;
    *len = 0;
    if (fd < 0) return -1;
    while (*len < max && (r = read(fd, buf + *len, max - *len)) > 0) *len += (uint32_t)r;
    close(fd);
    return 0;
}

// ---- one navigation command: 12 bytes, opcode word + two operands -------------------------------------------------
static const uint8_t *cmd(uint32_t obj, uint32_t i)
{
    if (obj >= nobj || i >= obj_n[obj]) return 0;
    return mobj + obj_cmds[obj] + i * 12;
}
static uint32_t opcnt(const uint8_t *c)  { return be32(c) >> 29; }
static uint32_t grp(const uint8_t *c)    { return be32(c) >> 27 & 3; }
static uint32_t subgrp(const uint8_t *c) { return be32(c) >> 24 & 7; }
static uint32_t imm1(const uint8_t *c)   { return be32(c) >> 23 & 1; }
static uint32_t imm2(const uint8_t *c)   { return be32(c) >> 22 & 1; }
static uint32_t bropt(const uint8_t *c)  { return be32(c) >> 16 & 15; }
static uint32_t cmpopt(const uint8_t *c) { return be32(c) >> 8 & 15; }

#define PSR20    0x80000014u
#define CMP_EQ   2
#define CMP_NE   3
static int region_bit(uint32_t v) { return v == 1 || v == 2 || v == 4; }

// "EQ/NE PSR20, imm" (either operand order) with a single region bit -> *r
static int psr20_cmp(const uint8_t *c, uint32_t op, uint32_t *r)
{
    uint32_t a, b;
    if (!c || grp(c) != 1 || opcnt(c) < 2 || cmpopt(c) != op) return 0;
    a = be32(c + 4); b = be32(c + 8);
    if (!imm1(c) && a == PSR20 && imm2(c) && region_bit(b)) { *r = b; return 1; }
    if (imm1(c) && region_bit(a) && !imm2(c) && b == PSR20) { *r = a; return 1; }
    return 0;
}
// "JumpTitle imm" -> *t
static int jump_title(const uint8_t *c, uint32_t *t)
{
    if (!c || grp(c) != 0 || subgrp(c) != 1 || bropt(c) != 1 || !opcnt(c) || !imm1(c)) return 0;
    *t = be32(c + 4);
    return 1;
}
// PlayPL / PlayPLatPI / PlayPLatMK
static int play_cmd(const uint8_t *c) { return c && grp(c) == 0 && subgrp(c) == 2 && bropt(c) < 3; }
// "GoTo imm" -> *n
static int go_to(const uint8_t *c, uint32_t *n)
{
    if (!c || grp(c) != 0 || subgrp(c) != 0 || bropt(c) != 1 || !opcnt(c) || !imm1(c)) return 0;
    *n = be32(c + 4);
    return 1;
}
// title number (1.., 0xffff = top menu) -> HDMV movie object
static int title_to_obj(uint32_t t, uint32_t *obj)
{
    if (t == 0) return 0;
    if (t == 0xffff) { if (!top_hdmv) return 0; *obj = top_obj; }
    else { if (t > ntitle || !title_hdmv[t - 1]) return 0; *obj = title_obj[t - 1]; }
    return *obj < nobj;
}

// ---- files -------------------------------------------------------------------------------------------------------
static int parse_mobj(void)
{
    uint32_t off = 0x32;
    if (mlen < 0x32 || memcmp(mobj, "MOBJ", 4)) return 0;
    nobj = be16(mobj + 0x30);
    if (nobj == 0 || nobj > MAX_OBJ) return 0;
    for (uint32_t o = 0; o < nobj; o++) {
        uint32_t n;
        if (off + 4 > mlen) return 0;
        n = be16(mobj + off + 2);
        if (off + 4 + n * 12 > mlen) return 0;
        obj_cmds[o] = off + 4; obj_n[o] = (uint16_t)n;
        off += 4 + n * 12;
    }
    return 1;
}
// First Play / Top Menu / title entry: 2 bits object type (1 = HDMV), the HDMV object id at +6
static int index_item(uint32_t off, int *hdmv, uint16_t *obj)
{
    if (off + 12 > ilen) return 0;
    *hdmv = be32(indx + off) >> 30 == 1;
    *obj = *hdmv ? be16(indx + off + 6) : 0xffff;
    return 1;
}
static int parse_index(void)
{
    uint32_t s;
    int h;
    if (ilen < 16 || memcmp(indx, "INDX", 4)) return 0;
    s = be32(indx + 8);
    if (s + 0x1e > ilen) return 0;
    if (!index_item(s + 4, &fp_hdmv, &fp_obj) || !index_item(s + 16, &top_hdmv, &top_obj)) return 0;
    ntitle = be16(indx + s + 0x1c);
    if (ntitle > MAX_TTL || s + 0x1e + ntitle * 12u > ilen) return 0;
    for (uint32_t t = 0; t < ntitle; t++) {
        if (!index_item(s + 0x1e + t * 12, &h, &title_obj[t])) return 0;
        title_hdmv[t] = (uint8_t)h;
    }
    return 1;
}

// ---- the two checks ----------------------------------------------------------------------------------------------
static uint32_t check_ne(uint32_t fp)
{
    for (uint32_t i = 0; i + 1 < obj_n[fp]; i++) {
        uint32_t r, w, wo, r2, t2, back;
        if (!psr20_cmp(cmd(fp, i), CMP_NE, &r) || !jump_title(cmd(fp, i + 1), &w)) continue;
        if (!title_to_obj(w, &wo) || obj_n[wo] <= 3) continue;
        for (uint32_t j = 0; j + 3 < obj_n[wo]; j++)
            if (psr20_cmp(cmd(wo, j), CMP_EQ, &r2) && r2 == r && jump_title(cmd(wo, j + 1), &t2)
                && play_cmd(cmd(wo, j + 2)) && jump_title(cmd(wo, j + 3), &back) && back == w)
                return r;
    }
    return 0;
}
// the warning title: at most 5 commands, its first Play among the first three, followed by "GoTo 0" as the last
static int warning_loop(uint32_t wo)
{
    uint32_t n = obj_n[wo], g;
    if (n < 1 || n > 5) return 0;
    for (uint32_t m = 0; m < n; m++) {
        if (!play_cmd(cmd(wo, m))) continue;
        return m < 3 && m + 1 < n && go_to(cmd(wo, m + 1), &g) && g == 0 && m + 2 == n;
    }
    return 0;
}
static uint32_t check_eq(uint32_t fp)
{
    uint32_t n = obj_n[fp];
    for (uint32_t i = 0; i + 1 < n; i++) {
        uint32_t r1, w;
        if (!psr20_cmp(cmd(fp, i), CMP_EQ, &r1) || !jump_title(cmd(fp, i + 1), &w)) continue;
        for (uint32_t k = i + 2; k + 1 < n; k++) {
            uint32_t r2, w2, wo;
            if (!psr20_cmp(cmd(fp, k), CMP_EQ, &r2) || !jump_title(cmd(fp, k + 1), &w2)) continue;
            if (r2 == r1 || w2 != w || !title_to_obj(w, &wo) || !warning_loop(wo)) continue;
            for (uint32_t m = k + 2; m < n && m <= k + 5; m++) {
                uint32_t t, mask = r1 | r2;
                if (!jump_title(cmd(fp, m), &t)) continue;
                if (t == w) continue;
                if (t != 0 && (mask == 3 || mask == 5 || mask == 6)) return mask ^ 7;
                break;
            }
        }
    }
    return 0;
}

int main(int argc, char **argv)
{
    char ipath[512];
    const char *slash;
    uint32_t r = 0;
    if (argc != 2) { fputs("usage: bdhdmv <path to BDMV/MovieObject.bdmv>\n", stderr); return 2; }
    slash = strrchr(argv[1], '/');
    if (!slash || (size_t)(slash - argv[1]) + 12 > sizeof ipath) { puts("UNKNOWN"); return 1; }
    memcpy(ipath, argv[1], (size_t)(slash - argv[1]) + 1);
    strcpy(ipath + (slash - argv[1]) + 1, "index.bdmv");
    if (read_all(argv[1], mobj, MOBJ_MAX, &mlen) || read_all(ipath, indx, INDX_MAX, &ilen)
        || !parse_mobj() || !parse_index() || !fp_hdmv || fp_obj >= nobj) { puts("UNKNOWN"); return 1; }
    r = check_ne(fp_obj);
    if (!r) r = check_eq(fp_obj);
    puts(r == 1 ? "A" : r == 2 ? "B" : r == 4 ? "C" : "UNKNOWN");
    return r ? 0 : 1;
}
