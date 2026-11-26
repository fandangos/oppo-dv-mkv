// oppo-dv-mkv: external subtitles of discs (BD ISO + Title.srt / .ssa / .ass), one cue cleaned in place. Replaces the
// player's own cue clean-up (RU 65-0131 0x93fc58, 142 bytes, Thumb), called by its SRT (8-bit / UTF-8 and UTF-16) and
// SSA/ASS parsers before a cue is stored. As the player's: "\N" becomes a line break ("\n\r") and {\...} override
// blocks go; new: every <tag ...> and </tag> goes too (the player only skipped one <i> <b> <u> <font> at the start of
// a line, so "</i>" and tags inside a line were drawn as text). A '<' that does not start a tag stays text.
// Built position independent and without calls: it is copied over the original function.
__attribute__((section(".text.extsub"), used)) void extsub_clean(char *s)
{
    char *r = s, *w = s;
    while (*r) {
        char c = *r;
        if (c == '\\' && r[1] == 'N') { *w++ = '\n'; *w++ = '\r'; r += 2; continue; }
        {   // {\...} and <tag ...> / </tag>: one skip, ending at '}' or '>'
            char *k = r + 1, end = 0;
            if (c == '{' && *k == '\\') end = '}';
            else if (c == '<') { if (*k == '/') k++; if ((unsigned char)((*k | 0x20) - 'a') < 26) end = '>'; }
            if (end) {
                while (*k && *k != end && *k != '<') k++;
                if (*k == end) { r = k + 1; continue; }
            }
        }
        *w++ = c; r++;
    }
    *w = 0;
}
