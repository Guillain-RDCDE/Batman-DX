import sys
a=open(sys.argv[1],'rb').read(); b=open(sys.argv[2],'rb').read()
assert len(b)>=len(a)
grow=len(b)-len(a)                           # Plus edition: the cartridge grows from 128 KB to 256 KB
a_safe=a+bytes([255])*grow                   # the new banks start empty ($FF)
# safeguard: outside the declared hooks, added code may only overwrite free space ($FF)
import re,os
allow=set()
if os.path.exists('build/dx.map'):
    for l in open('build/dx.map'):
        mm=re.search(r'SECTION: \$([0-9a-f]{4})-\$([0-9a-f]{4}) \(\$[0-9a-f]+ bytes\) \["([^"]+)"\]',l)
        if mm: allow.add(mm.group(3))
HOOK=('hook_',)
bank=None; bad=[]
if os.path.exists('build/dx.map'):
    for l in open('build/dx.map'):
        mb=re.search(r'bank #(\d+)',l)
        if mb: bank=int(mb.group(1))
        mm=re.search(r'SECTION: \$([0-9a-f]{4})-\$([0-9a-f]{4}) \(\$[0-9a-f]+ bytes\) \["([^"]+)"\]',l)
        if mm and not mm.group(3).startswith(HOOK):
            lo,hi=int(mm.group(1),16),int(mm.group(2),16)
            base=lo if bank==0 else bank*0x4000+lo-0x4000
            for k in range(hi-lo+1):
                if a_safe[base+k]!=0xFF: bad.append((mm.group(3),bank,lo+k)); break
if bad: raise SystemExit('ERROR: added code overwrites the game: %s'%bad)
out=bytearray(b'PATCH'); i=0; n=len(a); recs=0; tot=0
while i<n:
    if a[i]==b[i]: i+=1; continue
    j=i; last=i
    while j<n and j-i<0xFFFF:
        if a[j]!=b[j]: last=j
        elif j-last>8: break
        j+=1
    seg=b[i:last+1]
    if i==0x454F46: raise SystemExit("offset EOF")
    out+=i.to_bytes(3,'big')+len(seg).to_bytes(2,'big')+seg; recs+=1; tot+=len(seg); i=last+1
# the added half of the cartridge: runs of one repeated byte as RLE records, the rest as plain records
i=len(a); n=len(b)
while i<n:
    j=i
    while j<n and b[j]==b[i] and j-i<0xFFFF: j+=1
    if j-i>=8:
        out+=i.to_bytes(3,'big')+(0).to_bytes(2,'big')+(j-i).to_bytes(2,'big')+bytes([b[i]]); recs+=1; tot+=j-i; i=j; continue
    k=i
    while k<n and k-i<0xFFFF:
        r=k
        while r<n and b[r]==b[k] and r-k<8: r+=1
        if r-k>=8: break
        k=r
    seg=b[i:k]; out+=i.to_bytes(3,'big')+len(seg).to_bytes(2,'big')+seg; recs+=1; tot+=len(seg); i=k
out+=b'EOF'
open(sys.argv[3],'wb').write(out)
# check: replay the patch
c=bytearray(a); p=5
while out[p:p+3]!=b'EOF' or p+3!=len(out):
    o=int.from_bytes(out[p:p+3],'big'); l=int.from_bytes(out[p+3:p+5],'big')
    if l: data=out[p+5:p+5+l]; p+=5+l
    else: r=int.from_bytes(out[p+5:p+7],'big'); data=bytes([out[p+7]])*r; p+=8
    if len(c)<o+len(data): c.extend(bytes(o+len(data)-len(c)))
    c[o:o+len(data)]=data
assert bytes(c)==b, "the IPS does not give back the ROM"
print("IPS: %d records, %d bytes changed, file %d bytes - verified"%(recs,tot,len(out)))
