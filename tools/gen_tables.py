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
PLUS=bool(J.get('plus'))
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
    assert len(tab)==256 and all(0<=t<(16 if PLUS else 8) for t in tab),n      # Plus edition: bit 3 = tile taken from video bank 1
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
# Plus edition: logo -> title fade. 16 steps of 64 bytes (the 8 background palettes): 8 for the logo fading out (7/8 to 0),
# 8 for the title fading in (1/8 to 8/8). The logo = the title palettes with the logo golds (LogoGold, src/dx.asm) in
# palettes 1, 3-7.
if PLUS:
    GOLD=[0x43,0x00,0xD6,0x05,0x7F,0x23,0x43,0x00,0xD5,0x09,0xDF,0x53,0x43,0x00,0x51,0x01,0xBC,0x0E,
          0x43,0x00,0x0F,0x01,0x19,0x06,0x43,0x00,0xEE,0x00,0x75,0x01,0x43,0x00,0x73,0x05,0x5B,0x0E]
    title=pals(T.get('bg')); logo=list(title)
    for i,pn in enumerate((1,3,4,5,6,7)): logo[pn*8+2:pn*8+8]=GOLD[i*6:i*6+6]
    def dim(b,k):
        o_=[]
        for j in range(0,64,2):
            v=b[j]|(b[j+1]<<8); r,g,bl=v&31,(v>>5)&31,(v>>10)&31
            v=round(r*k/8)|(round(g*k/8)<<5)|(round(bl*k/8)<<10); o_+=[v&255,v>>8]
        return o_
    fd=[]
    for e in range(16): fd+=dim(logo,7-e) if e<8 else dim(title,e-7)
    o.append('MACRO FadeData\n'+db(fd)+'\nENDM')
o.append('MACRO SceneBlocks\n'+'\n'.join(blk[:10])+'\nENDM')
o.append('MACRO SceneBlocks2\n'+'\n'.join(blk[10:])+'\nENDM')
def tighten(pe):
    """Plus edition: drop a write that a later one entirely covers (same video bank, address and length, no bank
    switch in between), then merge writes that follow each other in memory (255 bytes at most)."""
    pe=[[a,list(d)] for a,d in pe]; keep=[True]*len(pe)
    for i,(a,d) in enumerate(pe):
        if a==0xFF4F: continue
        for j in range(i+1,len(pe)):
            if pe[j][0]==0xFF4F: break
            if pe[j][0]==a and len(pe[j][1])==len(d): keep[i]=False; break
    pe=[e for e,k in zip(pe,keep) if k]; out=[]
    for a,d in pe:
        if out and a!=0xFF4F and out[-1][0]!=0xFF4F and out[-1][0]+len(out[-1][1])==a and len(out[-1][1])+len(d)<=255:
            out[-1][1]+=d
        else: out.append([a,list(d)])
    return out
# ---- status bar (icon, gauge), sky gradient, nightfall, extra retouches (bank 4; bank 8 and 10 in the Plus edition)
H=J.get('status_icons')
o.append('DEF HUD_ON EQU %d'%(1 if H else 0)); o.append('DEF EXTRA_BANK EQU %d'%(8 if PLUS else 4)); o.append('DEF PLUS EQU %d'%(1 if PLUS else 0))
if H:
    o.append('MACRO HudXData\n'+db([S.get(n,{}).get('hud_x',0xFF) if S.get(n,{}).get('hud_x') is not None else 0xFF for n in SCENES])+'\nENDM')
    hc=[]
    for c in H['colors']: v=c15(c); hc+=[v&255,v>>8]
    o.append('MACRO HudColsData\n'+db(hc)+'\nENDM')
    jg=[]
    for e in range(5): v=c15(H['gauge'][e]); jg+=[v&255,v>>8]
    o.append('MACRO GaugeData\n'+db(jg)+'\nENDM')
    gl=[]; gd=[]
    for i,n in enumerate(SCENES):
        d=S.get(n,{}).get('gradient')
        if not d: continue
        gl.append('    db %d\n    dw Grad_%d'%(i,i))
        b=[]
        for e_ in d:
            line,c=e_[0],e_[1]; v=c15(c)
            if PLUS:   # Plus edition: line, palette index, target register (0x69 = rBCPD, 0x43 = SCX), two colors
                v2=c15(e_[2] if len(e_)>2 else (S[n]['bg'][0][1]))
                b+=[line,(e_[3] if len(e_)>3 else 0x80),(e_[4] if len(e_)>4 else 0x69),v&255,v>>8,v2&255,v2>>8]
            else: b+=[line,v&255,v>>8]
        gd.append('Grad_%d:\n'%i+db(b+[0xFF]))
    o.append('MACRO GradListData\n'+'\n'.join(gl+['    db $FF']+gd)+'\nENDM')
    ex=[]; tb=[]; fx=[]
    FAR=set(J.get('far_scenes') or [])         # Plus edition: scenes whose retouches are stored in bank FAR_BANK
    for i,n in enumerate(SCENES):
        pe=S.get(n,{}).get('patch_extra') or []
        if not pe: tb.append('    dw 0'); continue
        pt=[]
        if PLUS: pe=tighten(pe)                    # Plus edition only: the published edition keeps its bytes
        for addr,data in pe: pt+=[len(data),addr&255,addr>>8]+data
        if n in FAR:
            tb.append('    dw Extra_%d | $8000'%i); fx.append('Extra_%d: ; %s\n'%(i,n)+db(pt+[0]))
        else:
            tb.append('    dw Extra_%d'%i); ex.append('Extra_%d: ; %s\n'%(i,n)+db(pt+[0]))
    o.append('MACRO ExtraData\n'+'\n'.join(tb+ex)+'\nENDM')
    o.append('MACRO FarExtraData\n'+('\n'.join(fx) if fx else '    db 0')+'\nENDM')
    PS=[i for i,n in enumerate(SCENES) if n in (J.get('parallax') or [])]+[0xFE,0xFE]
    o.append('DEF PARA_A EQU %d'%PS[0]); o.append('DEF PARA_B EQU %d'%PS[1])
    # Plus edition: scenery added to the level, by stage -> (address in level memory, tile)
    lt=[]; ld_=[]
    TPL=J.get('templates') or {}; done={}
    for st_,cells in sorted((J.get('levels') or {}).items(),key=lambda kv:int(kv[0])):
        if st_ in TPL:                             # form 2: template (size, N columns x 16) + list of exceptions
            gb=TPL[st_]; assert len(gb)%16==0 and 16<=len(gb)<=256 and all(0<=v<256 for v in gb)
            b=[len(gb)&255]+list(gb)
            for adr,t in cells: b+=[adr&255,adr>>8,t]
            same=[k for k,v in done.items() if v==b]
            if same: lt.append('    db %d,2\n    dw Level_%s'%(int(st_),same[0])); continue     # same scenery as another stage: one copy
            done[st_]=b
            lt.append('    db %d,2\n    dw Level_%s'%(int(st_),st_))
            ld_.append('Level_%s:\n'%st_+db(b+[0,0])); continue
        dense=len(cells)*3>5120                    # many cells: one byte per level cell (0 = nothing)
        lt.append('    db %d,%d\n    dw Level_%s'%(int(st_),1 if dense else 0,st_)); b=[]
        if dense:
            b=[0]*5120
            for adr,t in cells: assert t!=0 and 0xCC00<=adr<0xE000; b[adr-0xCC00]=t
            ld_.append('Level_%s:\n'%st_+db(b))
        else:
            for adr,t in cells: b+=[adr&255,adr>>8,t]
            ld_.append('Level_%s:\n'%st_+db(b+[0,0]))
    fl=[]
    for st_,runs in sorted((J.get('far_levels') or {}).items(),key=lambda kv:int(kv[0])):   # form 3: in bank FAR_BANK
        lt.append('    db %d,3\n    dw FarLevel_%s'%(int(st_),st_)); b=[]
        for adr,data in runs: assert 0<len(data)<256 and 0xCC00<=adr and adr+len(data)<=0xE000; b+=[len(data),adr&255,adr>>8]+data
        fl.append('FarLevel_%s:\n'%st_+db(b+[0]))
    o.append('MACRO LevelData\n'+'\n'.join(lt+['    db 0']+ld_)+'\nENDM')
    o.append('MACRO FarLevelData\n'+('\n'.join(fl) if fl else '    db 0')+'\nENDM')
    # Plus edition: what a broken block leaves, by stage -> (address in level memory, tile)
    rt=[]; rd_=[]
    for st_,cells in sorted((J.get('remnants') or {}).items(),key=lambda kv:int(kv[0])):
        rt.append('    db %d\n    dw Remnant_%s'%(int(st_),st_)); b=[]
        for adr,t in cells: b+=[adr&255,adr>>8,t]
        rd_.append('Remnant_%s:\n'%st_+db(b+[0,0]))
    o.append('MACRO RemnantData\n'+'\n'.join(rt+['    db 0']+rd_)+'\nENDM')
    # Plus edition: living colors: 64 steps, each = color 0 of palette X then the two colors of the first three line steps
    VS=[(i,S[n]['life']) for i,n in enumerate(SCENES) if S.get(n,{}).get('life')]
    vl=[]; vt=[]
    for i,Vv in VS:
        assert len(Vv)==64 and all(len(c)==7 for c in Vv) and len(S[SCENES[i]]['gradient'][0])>3 and len(S[SCENES[i]]['gradient'])>=3; vb=[]
        for step in Vv:
            for c in step: v=c15(c); vb+=[v&255,v>>8]
        vl.append('    db %d\n    dw Life_%d'%(i,i)); vt.append('Life_%d:\n'%i+db(vb))
    o.append('MACRO LifeData\n'+'\n'.join(['LifeList:']+vl+['    db $FF']+vt)+'\nENDM')
    # nightfall (one scene): color ramp, offset for each level page, wave and window colors for each offset
    NS=[(i,S[n]['nightfall']) for i,n in enumerate(SCENES) if S.get(n,{}).get('nightfall')]
    if NS:
        i,Nn=NS[0]; ne=Nn.get('steps',len(S[SCENES[i]]['gradient']))
        o.append('DEF NIGHT_SCENE EQU %d'%i); o.append('DEF NIGHT_STEPS EQU %d'%ne); o.append('DEF NIGHT_PAGES EQU %d'%len(Nn['pages']))
        o.append('DEF NIGHT_FIRST EQU %d'%Nn.get('first',0))
        assert max(Nn['pages'])+ne<=len(Nn['ramp']) and len(Nn['waves'])>=max(Nn['pages'])+1
        rb=[]
        for c in Nn['ramp']: v=c15(c); rb+=[v&255,v>>8]
        vb=[]
        for c in Nn['waves']: v=c15(c); vb+=[v&255,v>>8]
        fb=[]
        for a_,b_ in Nn['windows']:
            for c in (a_,b_): v=c15(c); fb+=[v&255,v>>8]
        o.append('MACRO NightPagesData\n'+db(Nn['pages'])+'\nENDM'); o.append('MACRO NightRampData\n'+db(rb)+'\nENDM')
        o.append('MACRO NightWavesData\n'+db(vb)+'\nENDM'); o.append('MACRO NightWindowsData\n'+db(fb)+'\nENDM')
    else:
        o.append('DEF NIGHT_SCENE EQU $FE'); o.append('DEF NIGHT_STEPS EQU 1'); o.append('DEF NIGHT_PAGES EQU 1'); o.append('DEF NIGHT_FIRST EQU 0')
        o.append('MACRO NightPagesData\n    db 0\nENDM'); o.append('MACRO NightRampData\n    db 0,0\nENDM')
        o.append('MACRO NightWavesData\n    db 0,0\nENDM'); o.append('MACRO NightWindowsData\n    db 0,0,0,0\nENDM')
os.makedirs('build',exist_ok=True)
open('build/scenes.inc','w').write('\n'.join(o)+'\n')
