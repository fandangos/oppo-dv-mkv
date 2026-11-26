// oppo-dv-mkv bdregion hook (RAM only, the jailbreak's free .text1 area at 0x1c03a00). Two entries:
//  - gate_c (from gate.S): a BD-J disc asks for PSR20 (the player's region) on a physical disc: answer it from the
//    mailbox, filled by bdregiond; when empty, ask (REQUEST) and wait at most 10 s. No answer: the player's own value.
//  - bdr_ipcd: the player's ipcd_exec import (GOT 0x11d8e40). The command runs first; when it mounted a disc image on
//    /mnt/iso or linked a folder to /mnt/link, bdregiond is asked to set the region (vreq) and the player waits for it
//    (at most 8 s) before it goes on to play.
// Idea and the places in the player: autoABC by DamnFine815 (MIT); written for oppo-dv-mkv, no code copied.
#include "hook.h"
typedef unsigned u32;
__attribute__((section(".hdr"), used)) struct bdr_hdr H = { BDR_MAGIC };
#define ACCESS ((int (*)(const char *, int))0x000306f8)   /* access PLT, ARM */
#define USLEEP ((int (*)(u32))0x0003294c)                 /* usleep PLT, ARM */

static int physical(void)
{
    return ACCESS("/mnt/disc_00_0/BDMV/MovieObject.bdmv", 0) == 0 || ACCESS("/mnt/sr0/BDMV/MovieObject.bdmv", 0) == 0;
}
static int answer(u32 v) { return v == 1 || v == 2 || v == 4; }

int gate_c(void)
{
    u32 v;
    if (!H.enable || !physical()) return 0;
    H.gate_calls++;
    v = H.mailbox;
    if (v == MB_PASS) return 0;
    if (!answer(v)) {
        if (v == MB_EMPTY) H.mailbox = MB_REQUEST;
        for (int i = 0; i < 2000; i++) {                  // 2000 x 5 ms
            v = H.mailbox;
            if (answer(v) || v == MB_PASS) break;
            USLEEP(5000);
        }
        if (!answer(v)) { if (v != MB_PASS) H.gate_timeouts++; return 0; }
    }
    H.gate_answers++;
    return (int)v;
}

static int starts(const char *s, const char *p) { while (*p) if (*s++ != *p++) return 0; return 1; }
static int has(const char *s, const char *p)
{
    for (; *s; s++) { const char *a = s, *b = p; while (*b && *a == *b) { a++; b++; } if (!*b) return 1; }
    return 0;
}

int bdr_ipcd(const char *cmd, int a, int b, int c)
{
    int r = H.orig_ipcd(cmd, a, b, c);
    u32 k = 0;
    if (!H.enable || !cmd) return r;
    if (starts(cmd, "mount ") && has(cmd, "/mnt/iso")) k = 1;
    else if (starts(cmd, "ln -s ") && has(cmd, "/mnt/link")) k = 2;
    if (!k) return r;
    H.vreqs++;
    H.vreq = k;
    for (int i = 0; i < 1600 && H.vreq; i++) USLEEP(5000);   // 1600 x 5 ms
    if (H.vreq) { H.vreq = 0; H.vtimeouts++; }
    return r;
}
