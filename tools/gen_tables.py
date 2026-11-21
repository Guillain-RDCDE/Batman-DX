# Generates build/scenes.inc from src/moods/<mood>.json
# usage: python3 tools/gen_tables.py src/moods/dx.json
import json,os,sys
SCENES=['text','title','gotham','plant','jack','museum','batwing1','batwing2','cathedral','joker',
        'scene1','scene2','scene3','scene4','scene5','credits']
GFX_A={0x00:'text',0x02:'title',0x1B:'gotham',0x1C:'plant',0x0E:'jack',0x1D:'museum',0x17:'batwing1',0x19:'batwing2',0x1E:'cathedral',0x10:'joker'}
GFX_B={0x00:'scene1',0x04:'scene2',0x08:'scene3',0x0C:'scene4',0x10:'scene5',0x15:'credits'}
NA,NB=0x1F,0x17
GRIS=[[31,31,31],[21,21,21],[10,10,10],[0,0,0]]
J=json.load(open(sys.argv[1]))
S=J.get('scenes',{})
def c15(c): r,g,b=c; return r|(g<<5)|(b<<10)
def pals(lst):
    out=[]
    for i in range(8):
        p=lst[i] if lst and i<len(lst) and lst[i] else GRIS
        for c in p: v=c15(c); out+=[v&255,v>>8]
    return out
o=[]
o.append('DEF NB_SCENES EQU %d'%len(SCENES)); o.append('DEF NB_GFX_A EQU $%02X'%NA); o.append('DEF NB_GFX_B EQU $%02X'%NB)
def db(b): return '\n'.join('    db '+','.join('$%02X'%x for x in b[i:i+16]) for i in range(0,len(b),16))
o.append('MACRO SceneTabAData\n'+db([SCENES.index(GFX_A[i]) if i in GFX_A else 0xFF for i in range(NA)])+'\nENDM')
o.append('MACRO SceneTabBData\n'+db([SCENES.index(GFX_B[i]) if i in GFX_B else 0xFF for i in range(NB)])+'\nENDM')
o.append('MACRO SceneTableData\n'+'\n'.join('    dw Scene_%d'%i for i in range(len(SCENES)))+'\nENDM')
blk=[]
for i,n in enumerate(SCENES):
    s=S.get(n,{})
    tab=s.get('tab') or [0]*256
    assert len(tab)==256 and all(0<=t<8 for t in tab),n
    hud=s.get('hud',-1)
    pt=[]
    for addr,data in s.get('patch',[]): pt+=[len(data),addr&255,addr>>8]+data
    blk.append('Scene_%d: ; %s\n'%(i,n)+db(tab+pals(s.get('bg'))+pals(s.get('obj'))+[hud&0xFF]+pt+[0]))
# title shine: 16 steps, each giving color 3 of palettes 2 to 6 (the body of the letters, top to bottom)
T=S.get('title',{}); base=[(T.get('bg') or [None]*8)[i] for i in range(2,7)]
ec=[]
for ph in range(16):
    for r in range(5):
        c=base[r][3] if base[r] else [31,31,31]
        d=ph-9-r                                   # a light band sweeps down the letters
        if d==0: c=[31,31,31]
        elif d==1: c=[min(31,(c[0]+31)//2),min(31,(c[1]+31)//2),min(31,(c[2]+31)//2)]
        v=c15(c); ec+=[v&255,v>>8]
o.append('DEF SHINE EQU %d'%(1 if T.get('shine') else 0))
o.append('MACRO ShineData\n'+db(ec)+'\nENDM')
o.append('MACRO SceneBlocks\n'+'\n'.join(blk[:10])+'\nENDM')
o.append('MACRO SceneBlocks2\n'+'\n'.join(blk[10:])+'\nENDM')
os.makedirs('build',exist_ok=True)
open('build/scenes.inc','w').write('\n'.join(o)+'\n')
