// oppo-dv-mkv bdregion hook: shared header layout (the stub at 0x1c03a00, bdregion.sh and bdregiond read it)
#define BDR_BASE     0x1c03a00u
#define BDR_MAGIC    0x47524442u      /* "BDRG" */
#define MB_EMPTY     0u
#define MB_REQUEST   0x80000000u
#define MB_PASS      0xffffffffu
struct bdr_hdr {
    unsigned magic;                   // +0
    volatile unsigned enable;         // +4  1: answer / report; 0: everything passes through (the Extras switch)
    volatile unsigned mailbox;        // +8  PSR20 answer for BD-J on a physical disc: 0, REQUEST, 1/2/4, PASS
    volatile unsigned gate_calls;     // +12 getPSR(20) calls seen on a physical disc
    volatile unsigned gate_answers;   // +16 answered from the mailbox
    volatile unsigned gate_timeouts;  // +20 no answer in time (the player's own value)
    volatile unsigned vreq;           // +24 1 an image was mounted on /mnt/iso, 2 a folder linked to /mnt/link; the daemon clears it
    volatile unsigned vreqs;          // +28 virtual requests made
    volatile unsigned vtimeouts;      // +32 not cleared in time
    int (*orig_ipcd)(const char *, int, int, int);   // +36 the real ipcd_exec
    unsigned orig_word;               // +40 the first word of nGetPSR (put back by "off")
};
