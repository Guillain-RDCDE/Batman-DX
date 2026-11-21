# Writes the palette (bits 0-2) of each character piece into the pose data (bank 1, table $512A)
import sys,json,os
rom=sys.argv[1]; d=bytearray(open(rom,'rb').read())
J=json.load(open(sys.argv[2]))   # usage: patch_obj.py rom.gbc src/moods/<mood>.json
OT=J.get('objtile',{})      # { "pose": { "piece": palette } }  or  { "tile:XX": palette } (by tile number)
B=0x4000; base=0x512A; n=0
def rd(a): return d[B+a-0x4000]
NFR=119
for fr in range(NFR):
    p=rd(base+2*fr)|(rd(base+2*fr+1)<<8)
    h=rd(p); c=h&0x0F; var=2 if h&0x10 else 1
    for v in range(var):
        for i in range(c):
            o=B+p+1+(v*c+i)*4-0x4000
            t=d[o+2]
            pal=OT.get(str(fr),{}).get(str(i))
            if pal is None: pal=OT.get('tile:%02X'%t)
            if pal is not None:
                d[o+3]=(d[o+3]&0xF8)|(pal&7); n+=1
open(rom,'wb').write(d)
print("character pieces colored:",n)

# End credits: the statue's cape is a separate character (data at 6:757A, format: count, then dy, dx, tile, attribute).
# It gets palette 1 (the statue's blue); the signal in the sky (tiles DB-EA) keeps palette 0.
d=bytearray(open(rom,'rb').read()); o=0x1B57A; n=0
while True:
    c=d[o]
    if not (0<c<=16) or not all(0xAE<=d[o+1+4*i+2]<=0xDA for i in range(c)): break
    for i in range(c): d[o+1+4*i+3]=(d[o+1+4*i+3]&0xF8)|1; n+=1
    o+=1+4*c
open(rom,'wb').write(d)
print("cape pieces (credits):",n,"up to %X"%o)
