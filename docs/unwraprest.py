#!/usr/bin/env python3
# Reference tool (oppo-dv-mkv): unwrap NAL-63 EL slices that are not the first slice of their picture.
# Annex B in/out: python3 unwraprest.py in.hevc out.hevc. See docs/TECHNICAL.md, "Offline alternative".
import re,sys
d=open(sys.argv[1],'rb').read(); out=open(sys.argv[2],'wb')
pos=[m.start() for m in re.finditer(b'\x00\x00\x01',d)]
n=0
for i,p in enumerate(pos):
    s=p-1 if p>0 and d[p-1]==0 else p
    e=pos[i+1] if i+1<len(pos) else len(d)
    if i+1<len(pos) and d[pos[i+1]-1]==0: e=pos[i+1]-1
    sc=d[s:p+3]; body=d[p+3:e]
    if (body[0]>>1)&0x3f==63 and len(body)>4:
        it=(body[2]>>1)&0x3f
        if it<32 and not (body[4]&0x80): body=body[2:]; n+=1
    out.write(sc+body)
print('unwrapped',n)
