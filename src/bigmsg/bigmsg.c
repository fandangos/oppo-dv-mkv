// oppo-dv-mkv big message: several lines of large text in the player's tip popup (the bar behind "Zoom is not
// available for Dolby Vision content."), made taller and centred; used by the installer to say what to do after an
// install (remove the stick, unplug the player). Lives in the jailbreak's free .text1 tail at 0x1c07c00 (RWX).
// While a request is pending the player's usleep import (GOT) points at bg_usleep: the first player thread that sleeps
// claims it, does it and continues into the real usleep (as bootmsg). The tip's text widget is single-line: its style
// (in its content object: widget object +0x80 -> +0x40) gets the WGL multi-line bit (0x20) and "\n ends a line"
// (0x40000); a widget cannot be created from another app's thread. Until the next boot. Addresses: RU 65-0131.
typedef unsigned u32;
typedef unsigned short u16;
struct hdr { u32 magic; volatile u32 state; int (*orig)(u32); u32 ms; u32 shows; int ret; int err; int y; u32 h;
             u32 font_size; u32 r40; u32 r44; char text[256]; };
// state: 0 idle; 1 show requested -> 2 -> 3 shown (err: 0, or which step failed)
__attribute__((section(".hdr"), used)) struct hdr bg = { 0x4d474942, 0, 0, 0, 0, 0, 0, 0, 0, 2 };   /* "BIGM" */

#define HTYPE_OBJ  ((int (*)(u32, u16 *, u32 *))0x00784ccc)                   /* handle_get_type_obj */
#define WGL_DO_CMD ((int (*)(u32, u32, void *, void *))0x00740230)            /* c_wgl_do_cmd, ARM */
#define WGL_MOVE   ((int (*)(u32, int *, u32))0x007402f0)                     /* c_wgl_move, ARM */
#define WGL_VIS    ((int (*)(u32, u32))0x007404cc)                            /* c_wgl_set_visibility, ARM: 0 shown, 2 hidden */
#define SHOW_TMO   ((int (*)(u32, u32, u32, u32))0x00ac8345)                   /* widget show with timeout, Thumb */
#define HIDE_CB    0x0080cd35u                                                /* _misc_dv_lock_tip_ui_timeout_cb_wgl */
#define FRAME      (*(volatile u32 *)0x01344c74)                              /* h_id_frame_dv_lock_info (at 100,43) */
#define ICON       (*(volatile u32 *)0x01344c78)                              /* the red "not allowed" icon */
#define BAR        (*(volatile u32 *)0x01344c7c)                              /* h_id_frame_dv_lock_info_bg */
#define TEXT       (*(volatile u32 *)0x01344c80)                              /* h_id_text_dv_lock_info, child of BAR */
#define CMD_FONT   0x1007fc04u
#define CMD_TEXT   0x400f1402u
#define TIP_STYLE  0x00508001u
#define MULTILINE  0x00040020u
#define BAR_L 200
#define BAR_R 1520

static int prepare(void)
{
    u16 t = 0;
    u32 obj = 0, cnt, font[12];
    const char *n = "cinufnt_Default";
    volatile u32 *st;
    if (HTYPE_OBJ(TEXT, &t, &obj) || t != 0x3c5 || !obj) return -1;
    cnt = *(volatile u32 *)(obj + 0x80);
    if (!cnt) return -2;
    st = (volatile u32 *)(cnt + 0x40);
    if ((*st & ~MULTILINE) != TIP_STYLE) return -3;                 /* not the layout we know: leave it alone */
    *st |= MULTILINE;
    for (volatile int i = 0; i < 12; i++) font[i] = 0;              /* no memset in here */
    font[1] = bg.font_size;
    for (int i = 0; n[i]; i++) ((char *)&font[2])[i] = n[i];
    if (WGL_DO_CMD(TEXT, CMD_FONT, font, 0)) return -4;
    return 0;
}

static void show(void)
{
    unsigned short w[256];
    int r[4], n = 0;
    if ((bg.err = prepare()) != 0) return;
    while (n < 255 && bg.text[n]) { w[n] = (unsigned char)bg.text[n]; n++; }
    w[n] = 0;
    WGL_DO_CMD(TEXT, CMD_TEXT, w, (void *)n);
    WGL_VIS(ICON, 2);
    r[0] = 0; r[1] = 0; r[2] = BAR_R - BAR_L; r[3] = (int)bg.h;
    WGL_MOVE(TEXT, r, 0);
    r[0] = BAR_L; r[1] = bg.y; r[2] = BAR_R; r[3] = bg.y + (int)bg.h;
    WGL_MOVE(BAR, r, 0);
    bg.ret = SHOW_TMO(FRAME, bg.ms ? bg.ms : 6000, 1, HIDE_CB);
    bg.shows++;
}

int bg_usleep(u32 us)
{
    u32 s = 1;
    if (__atomic_compare_exchange_n(&bg.state, &s, 2, 0, __ATOMIC_ACQ_REL, __ATOMIC_RELAXED)) {
        show();
        __atomic_store_n(&bg.state, 3, __ATOMIC_RELEASE);
    }
    return bg.orig(us);
}
