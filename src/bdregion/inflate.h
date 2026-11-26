// oppo-dv-mkv bdregion: raw deflate decoder (RFC 1951), written from the specification. Included by bdj.c and cg.c.
// Needs <stdint.h> and <string.h>.
// ---- inflate (RFC 1951) into out[0..max) --------------------------------------------------------------------------
struct zin { const uint8_t *in; uint32_t n, pos, bit; uint8_t *out; uint32_t len, max; };
static int zbits(struct zin *z, int k, uint32_t *v)
{
    *v = 0;
    for (int i = 0; i < k; i++) {
        if (z->pos >= z->n) return 0;
        *v |= (uint32_t)(z->in[z->pos] >> z->bit & 1) << i;
        if (++z->bit == 8) { z->bit = 0; z->pos++; }
    }
    return 1;
}
struct huff { uint16_t count[16], sym[320]; };
static int hbuild(struct huff *h, const uint8_t *len, int n)
{
    uint16_t offs[16];
    int left = 1;
    memset(h->count, 0, sizeof h->count);
    for (int i = 0; i < n; i++) h->count[len[i]]++;
    if (h->count[0] == n) return 1;                     // no codes (a distance tree may be empty)
    for (int l = 1; l < 16; l++) { left <<= 1; left -= h->count[l]; if (left < 0) return 0; }
    offs[1] = 0;
    for (int l = 1; l < 15; l++) offs[l + 1] = (uint16_t)(offs[l] + h->count[l]);
    for (int i = 0; i < n; i++) if (len[i]) h->sym[offs[len[i]]++] = (uint16_t)i;
    return 1;
}
static int hdecode(struct zin *z, const struct huff *h)
{
    int code = 0, first = 0, index = 0;
    for (int l = 1; l < 16; l++) {
        uint32_t b;
        if (!zbits(z, 1, &b)) return -1;
        code |= (int)b;
        if (code - h->count[l] < first) return h->sym[index + code - first];
        index += h->count[l]; first += h->count[l]; first <<= 1; code <<= 1;
    }
    return -1;
}
static const uint16_t LBASE[29] = { 3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258 };
static const uint8_t LEXT[29] = { 0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0 };
static const uint16_t DBASE[30] = { 1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,
                                    4097,6145,8193,12289,16385,24577 };
static const uint8_t DEXT[30] = { 0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13 };
static int zcodes(struct zin *z, const struct huff *lh, const struct huff *dh)
{
    for (;;) {
        int s = hdecode(z, lh);
        uint32_t e, len, dist;
        if (s < 0) return 0;
        if (s < 256) { if (z->len >= z->max) return 0; z->out[z->len++] = (uint8_t)s; continue; }
        if (s == 256) return 1;
        s -= 257;
        if (s >= 29 || !zbits(z, LEXT[s], &e)) return 0;
        len = LBASE[s] + e;
        s = hdecode(z, dh);
        if (s < 0 || s >= 30 || !zbits(z, DEXT[s], &e)) return 0;
        dist = DBASE[s] + e;
        if (dist > z->len || z->len + len > z->max) return 0;
        for (; len; len--, z->len++) z->out[z->len] = z->out[z->len - dist];
    }
}
static int inflate(struct zin *z)
{
    static const uint8_t ORD[19] = { 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15 };
    uint32_t last = 0, type;
    while (!last) {
        struct huff lh, dh;
        uint8_t len[320];
        if (!zbits(z, 1, &last) || !zbits(z, 2, &type)) return 0;
        if (type == 0) {                                    // stored
            uint32_t n;
            if (z->bit) { z->bit = 0; z->pos++; }
            if (z->pos + 4 > z->n) return 0;
            n = (uint32_t)z->in[z->pos] | z->in[z->pos + 1] << 8;
            if ((n ^ ((uint32_t)z->in[z->pos + 2] | z->in[z->pos + 3] << 8)) != 0xffff) return 0;
            z->pos += 4;
            if (z->pos + n > z->n || z->len + n > z->max) return 0;
            memcpy(z->out + z->len, z->in + z->pos, n); z->pos += n; z->len += n;
            continue;
        }
        if (type == 1) {                                    // fixed codes
            int i = 0;
            for (; i < 144; i++) len[i] = 8;
            for (; i < 256; i++) len[i] = 9;
            for (; i < 280; i++) len[i] = 7;
            for (; i < 288; i++) len[i] = 8;
            if (!hbuild(&lh, len, 288)) return 0;
            for (i = 0; i < 30; i++) len[i] = 5;
            if (!hbuild(&dh, len, 30)) return 0;
        } else if (type == 2) {                             // dynamic codes
            uint32_t hl, hd, hc, v;
            struct huff ch;
            uint8_t cl[19] = { 0 };
            if (!zbits(z, 5, &hl) || !zbits(z, 5, &hd) || !zbits(z, 4, &hc)) return 0;
            hl += 257; hd += 1; hc += 4;
            if (hl > 286 || hd > 30) return 0;
            for (uint32_t i = 0; i < hc; i++) { if (!zbits(z, 3, &v)) return 0; cl[ORD[i]] = (uint8_t)v; }
            if (!hbuild(&ch, cl, 19)) return 0;
            for (uint32_t i = 0; i < hl + hd;) {
                int s = hdecode(z, &ch);
                uint32_t rep, sym = 0;
                if (s < 0) return 0;
                if (s < 16) { len[i++] = (uint8_t)s; continue; }
                if (s == 16) { if (!i || !zbits(z, 2, &rep)) return 0; sym = len[i - 1]; rep += 3; }
                else if (s == 17) { if (!zbits(z, 3, &rep)) return 0; rep += 3; }
                else { if (!zbits(z, 7, &rep)) return 0; rep += 11; }
                if (i + rep > hl + hd) return 0;
                while (rep--) len[i++] = (uint8_t)sym;
            }
            if (!len[256] || !hbuild(&lh, len, (int)hl) || !hbuild(&dh, len + hl, (int)hd)) return 0;
        } else return 0;
        if (!zcodes(z, &lh, &dh)) return 0;
    }
    return 1;
}

