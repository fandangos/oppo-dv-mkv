/* oppo-dv-mkv: bdpdrv1 kernel patch for Dolby Vision profile 7 (FEL/MEL) from single-track MKV.
 * Oppo UDP-203, MediaTek MT8581, "RU 65-0131" jailbreak firmware. Linked into the dead CLI test function
 * _FbmCli_Test_4K (0x7e98be80..0x7e98c7c0) of the bdpdrv1 module (always loaded at 0x7e8d3000 on this firmware).
 *
 * Hooks (see entry.S and docs/TECHNICAL.md):
 *  1. elfix()   i4VDEC_HAL_H265_InitBarrelShifter: in MKV/TS single-stream P7 the enhancement layer (EL) NALs are
 *               wrapped in NAL type 63 (00 00 01 7E 01 ...). The decoder's software start-code reader strips that
 *               wrapper, but the hardware slice finder of the EL decoder cannot: every 2nd..Nth slice of an EL
 *               picture fails. So, just before the EL decoder starts, each wrapped *continuation* slice
 *               (first_slice_segment_in_pic_flag = 0) is rewritten in place to 00 00 00 00 01 + slice (same length,
 *               legal Annex B). First slices and non-VCL NALs stay wrapped (the BL parser must still skip them).
 *  2. rdfix()   i4ESM_FifoRdPtrSet: the base layer (BL) and EL decoders share one video FIFO but release it through
 *               separate ESM handles; the MKV splitter refills according to the EL handle. The 1080p EL decodes far
 *               ahead of the 4K BL, so the splitter overwrote BL data before it was decoded. The EL's release is
 *               clamped to the BL's read pointer.
 *  3. sync_stub u4VDP_AssignSyncCtrl (entry.S): the MKV path gives the EL video plane (VDP1) an AV-sync controller but
 *               never the BL plane (VDP0); with audio as master this hard-locks the SoC when the EL plane starts.
 *               Unless VDP0 got one in the last 5 s (TS / Blu-ray keep stock flow), it is redirected to VDP0
 *               (lip sync like single-layer MKV).
 *  4. vdp_off() VDec_Stop: on STOP the MKV middleware never turns the EL plane off, which then scans out freed frame
 *               buffers (garbage on every screen until reboot). When the EL decoder stops, the plane is disabled.
 *  5. spsfix()  i4VDecH265SPSPsr call and
 *  6. ppfix()   vH265PreParseSPS call: after a seek / fast-forward the EL decoder can parse the BL's 4K SPS and decode
 *               EL pictures past the end of its 1080p buffers (green strips until reboot); such an SPS is rejected.
 *  7. clrfix()  vESM_FifoClear tail: a seek clears the BL's ESM handle but not the EL's (same FIFO memory); the EL
 *               decoded stale queue entries. Every other handle on the same FIFO is cleared too.
 *  8.-11.       Seek fixes in a second cave, _Cmd_ImgResz_TestPerformance (entry.S, assembly only): a stale
 *               "no frame buffer, re-parse" flag after a same-stream stop, the EL's multi-core reset after a stop
 *               that interrupted a BL picture, and the EL plane timing its frames against the BL plane's frozen
 *               pre-seek frame. Each left the EL plane empty after a seek, which freezes both planes.
 * 12. eos_stub  fgVDecRetrieveEsIsPic (second cave, entry.S): the EL decoder's last ES message at the end of the file
 *               is empty (no read pointer) and comes without the end-of-stream command; it was decoded as a picture
 *               at address 0 and the decoder thread crashed. Such a message now sets the EOS flag.
 * Since v1.4.0 hooks 4 and 8-12 act only in single-stream DV (stream info fgIsSingle, +0x650ac): UHD Blu-ray uses
 * the firmware's own dual-stream path, where the multi-core reset cut base-layer pictures short.
 *
 * Some struct fields below are left over from development; the layout is kept so the counters stay where the
 * installer's "status" output expects them. */
typedef unsigned int u32; typedef unsigned char u8;

extern void DOVI_CleanDCacheRange(u32 va, u32 len);
extern int printk(const char *fmt, ...);
extern volatile u32 jiffies;

struct st { u32 magic, calls, elaus, fixes, maxscan, lastrd, enable, bad, longs, longrd, longwhy, clrs;
            u32 clrbusy, elcalls, waits, timeouts, elw, elh, skipped, maxwait;
            u32 blrd, prevel, blcalls, gated;
            u32 rdcalls, rdfixed, rdtick, rdlag; u32 esa, eea; };
extern struct st elstat;

#define LIMIT (3u << 20)
/* bdpdrv1 global data offset. The shipped blob is built with 0 (RU 65-0131 layout); p7kel.sh moves these addresses by
 * the offset it measures on the player (USA build +0x90, another build +0x50). build.sh compiles other values to check that. */
#ifndef DSHIFT
#define DSHIFT 0u
#endif
#define ESM_TAB ((u32 **)(0x7ee41cacu + DSHIFT))
#define NOSC  (1u << 20)
#ifndef LOWMEM_LO
#define LOWMEM_LO 0x80000000u
#define LOWMEM_HI 0xc0000000u
#endif

/* scan EL AU from offset p; rewrite continuation slices if wr. returns bytes scanned; *el = saw wrapped NALs */
static u32 scan(u8 *b, u32 n, u32 p, u32 wr, u32 sa, u32 *el, u32 *fx, u32 *why, u32 lim)
{
    u32 i, z = 0, seen = 0, lastsc = 0;
#define AT(o) b[((o) >= n) ? (o) - n : (o)]
    *el = 0; *fx = 0; *why = 0;
    for (i = 0; i < lim; i++) {
        u32 o = p + i; if (o >= n) o -= n;
        u8 c = b[o];
        if (c == 0) { if (++z > 512) { *why = 1; break; } continue; }
        if (i - lastsc > NOSC) { *why = 2; break; }
        if (c != 1 || z < 2) { z = 0; continue; }
        z = 0; lastsc = i;
        u8 h0 = AT(o + 1), h1 = AT(o + 2);
        if (h0 == 0x7e && h1 == 0x01) {
            u8 t = (AT(o + 3) >> 1) & 0x3f;
            *el = 1;
            if (t < 32) {
                if (AT(o + 5) & 0x80) { if (seen) break; seen = 1; }
                else {
                    if (wr) {
                        u32 o1 = o + 1 >= n ? o + 1 - n : o + 1;
                        b[o] = 0; b[o1] = 0;   /* 01 7E 01 -> 00 00 01 */
                        DOVI_CleanDCacheRange(sa + o, 1);
                        DOVI_CleanDCacheRange(sa + o1, 1);
                    }
                    (*fx)++;
                }
            }
        } else {
            u8 t = (h0 >> 1) & 0x3f;
            if (!(t < 32 && !(AT(o + 3) & 0x80))) break;   /* only plain continuation slices may follow */
            if (!*el) break;                                  /* not inside an EL AU */
        }
    }
    if (i >= lim) *why = 3;
    return i;
}

void elfix(u32 *bs, u32 vld, u32 lr)
{
    struct st *s = &elstat;
    u32 rd = bs[0], ea = bs[1], sa = bs[2];
    s->calls++;
    u32 en = s->enable;
    if (!(en & 1)) return;
    if (sa < LOWMEM_LO || ea > LOWMEM_HI || sa >= ea || rd < sa || rd >= ea || ((sa | ea) & 0xfff)) { s->bad++; return; }
    if (sa == s->esa && s->eea > sa && s->eea < ea && rd < s->eea) ea = s->eea;   /* ESM ring end (bs end can be larger) */
    u8 *b = (u8 *)sa; u32 n = ea - sa, p = rd - sa, el, fx, why;
    u32 d = p >= s->prevel ? p - s->prevel : p + n - s->prevel;
    if (d < s->gated) return;  /* inside the EL AU handled last: nothing to do */
    /* never read past the data the splitter has written: stale lines pulled into the D-cache ahead of the
     * writer get read back by the CPU-side parsers after the FIFO is refilled -> garbage -> SoC hang */
    u32 lim = 0, h;
    for (h = 0; h < 64; h++) {
        u32 *e = ESM_TAB[h], *f;
        if (!e || !((u8 *)e)[0x28] || !(f = (u32 *)e[0]) || f[0] != sa) continue;
        u32 w = f[3];
        if (w < sa || w > ea) continue;
        w -= sa; w = w >= p ? w - p : w + n - p;
        if (w > lim) lim = w;
    }
    if (!lim) { s->bad++; return; }
    u32 len = scan(b, n, p, 0, sa, &el, &fx, &why, lim);
    if (why) s->longs++;
    if (!el || why) return;                      /* BL / other, or EL AU not complete */
    s->prevel = p; s->gated = len;               /* remember this EL AU */
    if (!fx) return;                             /* already rewritten */
    if (!(en & 2)) return;
    scan(b, n, p, 1, sa, &el, &fx, &why, lim);
    s->elaus++;
    s->fixes += fx;
}

/* i4ESM_FifoRdPtrSet(handle, rd) entry: in single-stream DV the BL and EL decoders release the SAME video FIFO memory
 * through separate ESM handles (separate fifo structs, same sa/ea); the splitter's free space follows the EL one.
 * The EL runs ahead, so its release let the splitter overwrite BL data not yet decoded. Returns the rd to use. */
static __attribute__((noinline)) u32 *esm_fifo(u32 h)
{
    u32 *e;
    if (h >= 64 || !(e = ESM_TAB[h]) || !((u8 *)e)[0x28]) return 0;
    return (u32 *)e[0];
}

/* VDEC per-ESID ESM handles (VDec_Update_Esm: base 0x7ee6e690 + 8 + esid*0x14, handle at +0xc): ESID 0 = BL, 1 = EL */
#define ESID_HANDLE(i) (*(volatile u32 *)((0x7ee6e6a4u + DSHIFT) + (i) * 0x14))
u32 rdfix(u32 h, u32 rd)
{
    struct st *s = &elstat;
    if (!(s->enable & 128)) return rd;
    u32 *f = esm_fifo(h);
    if (!f) return rd;
    u32 sa = f[0], ea = f[1], wr = f[3], n = ea - sa;
    if (rd < sa || rd > ea || wr < sa || wr > ea || !n) return rd;
    s->rdcalls++;
    u32 blh = ESID_HANDLE(0);
    if (h == blh || h == ESID_HANDLE(1)) { s->esa = sa; s->eea = ea; }   /* video FIFO only (audio/subtitles use this too) */
    if (h != ESID_HANDLE(1) || h == blh) return rd;
    u32 *fb = esm_fifo(blh);
    if (!fb || fb[0] != sa) return rd;           /* not single-stream DV (BL/EL in separate FIFOs) */
    /* only the EL's release is clamped to the BL's: the splitter follows the EL handle and the EL runs ahead */
    u32 o = fb[2];
    if (o < sa || o > ea) return rd;
    u32 mine = wr >= rd ? wr - rd : wr + n - rd, theirs = wr >= o ? wr - o : wr + n - o;
    if (theirs <= mine) return rd;
    s->rdfixed++;
    return o;
}

/* vESM_FifoClear(h) tail (seek, trick play, stop). In single-stream DV the EL decoder reads the video FIFO through its own
 * ESM handle, but the firmware only clears the BL's: the EL handle keeps its picture queue and read pointer from before
 * the seek, pointing at data the splitter has since overwritten. The EL decoder then decodes garbage (or the BL's SPS),
 * and both decoders stall. So every other handle on the same FIFO memory is cleared too. */
extern void vESM_FifoClear(u32 h);
void clrfix(u32 h)
{
    struct st *s = &elstat;
    u32 *f = esm_fifo(h), *g, i;
    if (!(s->enable & 4096) || s->clrbusy || !f) return;
    s->clrbusy = 1;                              /* vESM_FifoClear below comes back here */
    for (i = 0; i < 64; i++)
        if (i != h && (g = esm_fifo(i)) && g[0] == f[0]) { vESM_FifoClear(i); s->clrs++; }
    s->clrbusy = 0;
}

/* VDec_Stop(esid) entry. MKV single-stream DV: on STOP the middleware never disables the EL plane (VDP1); it stays
 * in state 2 scanning out freed EL frame buffers (garbage on every screen until reboot). On a natural end the firmware
 * calls VDP_SetEnable(1, 0) itself. So when the EL decoder (ESID 1) is stopped and VDP1 is still on, turn it off. */
#define VDP_G      ((volatile u32 *)(0x7ee3cb60u + DSHIFT))
extern u32 VDP_SetEnable(u32 id, u32 en);
void vdp_off(u32 esid)
{
    struct st *s = &elstat;
    u32 arr = VDP_G[0x34 / 4];
    if (!(s->enable & 1024) || esid != 1 || !arr || *(volatile u32 *)(arr + 0x880 + 0x118) != 2) return;
    s->waits++;
    VDP_SetEnable(1, 0);
}

/* i4VDecH265SPSPsr(ctx, sps_base, pic) call in i4H265_Parse_Syntax_Proc. After a seek in single-stream DV the EL
 * decoder (ESID 1) can start at a base-layer access unit and parse the BL's 3840x2160 SPS (same sps id as the EL's).
 * It then builds a 4K frame-buffer group, borrowing memory that the previous EL group still holds; after a few rapid
 * seeks the EL buffers overlap other memory (green strips in the EL picture until reboot). An SPS wider than 1920
 * on the EL decoder in single-stream DV mode is therefore rejected like a malformed one; the EL's own SPS follows.
 * The rejected SPS has overwritten the EL's slot (same id), and the EL frame-buffer group is rebuilt from that slot's
 * size: the EL's last size is put back, else the EL gets a 4K group and never decodes again (hang). */
extern u32 i4VDecH265SPSPsr(u32 ctx, u32 base, u32 pic);
#define ESINFO(i) (*(volatile u32 *)((0x7ee6e690u + DSHIFT) + 0xa8 + (i) * 4))
u32 spsfix(u32 ctx, u32 base, u32 pic)
{
    u32 r = i4VDecH265SPSPsr(ctx, base, pic), e;
    if (r || !(elstat.enable & 2048) || *(u8 *)(ctx + 0xd4) != 1 || !(e = ESINFO(1))) return r;
    if (*(u8 *)(e + 0x650ac) != 1 || *(u8 *)(e + 0x650af) != 1) return r;   /* not single-stream DV EL */
    u8 *sps = (u8 *)(base + *(u32 *)(base + 0x30) * 0x28a8);
    u32 *wh = (u32 *)(sps + 0x450);                     /* pic width, height */
    if (wh[0] <= 1920) { elstat.elw = wh[0]; elstat.elh = wh[1]; return r; }   /* the EL's own size */
    sps[0x2b4] = 0;                                     /* SPS not valid */
    if (elstat.elw) { wh[0] = elstat.elw; wh[1] = elstat.elh; }   /* frame buffers are sized from this slot */
    elstat.timeouts++;
    return 0xff03;
}

/* Same problem in the pre-parse that sizes the frame buffers when a decoder (re)starts after a seek or trick play:
 * vH265PreParseSPS(esid, .., .., .., out) with out = {w, h, x, valid} and the previous values saved at out[4..7].
 * For the EL decoder in single-stream DV a size wider than 1920 (the BL's SPS) is dropped: previous values back. */
extern void vH265PreParseSPS(u32 esid, u32 a, u32 b, u32 c, u32 *o);
void ppfix(u32 esid, u32 a, u32 b, u32 c, u32 *o)
{
    u32 e;
    vH265PreParseSPS(esid, a, b, c, o);
    if (esid != 1 || !(elstat.enable & 2048) || !(e = ESINFO(1)) || o[0] <= 1920) return;
    if (*(u8 *)(e + 0x650ac) != 1 || *(u8 *)(e + 0x650af) != 1) return;
    o[0] = o[4]; o[1] = o[5]; o[2] = o[6]; ((u8 *)o)[12] = ((u8 *)o)[28];
    elstat.timeouts++;
}
