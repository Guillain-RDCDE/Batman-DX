# Compares the original game (monochrome) with Batman DX (color or monochrome), game frame by game frame.
# Both games receive the same inputs, injected into the joypad reading routine. The input stream and the
# comparison restart from zero at every level load (routine $10D5): cutscenes advance with the sound, which runs
# on a clock independent of frames, and would otherwise shift everything that follows.
# Needs: pyboy.   usage: compare.py original.gb batman-dx.gbc stage frames series [--mono]
import sys,random,hashlib
from pyboy import PyBoy
A_ROM,B_ROM=sys.argv[1],sys.argv[2]; stage,N,seed=int(sys.argv[3]),int(sys.argv[4]),int(sys.argv[5]); mono='--mono' in sys.argv
BT={'right':0x10,'left':0x20,'up':0x40,'down':0x80,'a':1,'b':2,'select':4,'start':8}
def plan_for(k):
    rnd=random.Random(seed*1000+k); p=[0]*60; names=['a','a','b','b','right','right','right','right','left','up','down']
    while len(p)<N+100:
        b=BT[rnd.choice(names)]
        if rnd.random()<0.5: b|=0x10
        if rnd.random()<0.2: b|=BT[rnd.choice(['a','b'])]
        if rnd.random()<0.004: b=8
        p+=[b]*rnd.choice([2,4,8,20,30])+[0]*rnd.choice([0,1,2,6])
    return p
def run(rom,cgb):
    pb=PyBoy(rom,window='null',cgb=cgb,sound_emulated=False); m=pb.memory; r=pb.register_file
    S=dict(sync=0,reads=0,reads2=0,started=False,plan=plan_for(0),segs=[[]],ly={},total=0,ticks=0)
    def st(c):
        if stage: r.A=stage                # force the starting stage ($C0C2)
        S['started']=True
    pb.hook_register(0,0x0477,st,None)
    def joy(c):
        p=S['plan']; r.C=p[S['reads']] if S['reads']<len(p) else 0; S['reads']+=1
    def joy2(c):                           # reads during title effects: only START, to begin the game
        r.C=8 if (not S['started'] and 1400<=S['reads2']<1404) else 0; S['reads2']+=1
    for a in (0x0D1F,0x0E85): pb.hook_register(0,a,joy,None)
    pb.hook_register(0,0x0DC1,joy2,None)
    def level(c):                          # level load: synchronization point
        S['sync']+=1; S['reads']=0; S['plan']=plan_for(S['sync']); S['segs'].append([])
    pb.hook_register(0,0x10D5,level,None)
    def frame(c):
        w=bytearray(m[0xC000:0xCC00]); w[0x520:0x600]=bytes(0xE0); w[0x600:0x700]=bytes(256)   # the patch's own variables (the game never touches C520-C5FF)
        w[0x800:0xA00]=bytes(0x200); w[0xB00:0xC00]=bytes(0x100)                               # sound engine; screen buffer and stack
        w[0xB6:0xBD]=bytes(7)                                                                  # line effects of the stage title cards
        for i in range(3,0xA0,4): w[i]&=0xF0                                                   # color palette of characters
        # The game fills the character table from the start on one frame and from the end on the next (flag $FFFA)
        # to spread flicker. The direction depends on the number of frames elapsed since power-on, hence on the real
        # time spent on the title: we compare the characters displayed, not their order in the table.
        ent=sorted(bytes(w[i:i+4]) for i in range(0,0xA0,4)); w[0:0xA0]=b''.join(ent); w[0xA0]=0
        h=bytearray(m[0xFF80:0xFFFF]); h[0x40:0x70]=bytes(0x30); h[0x22]=0; h[0x7D]=0; h[3]&=0xF8; h[0x7A]=0
        lv=hashlib.md5(bytes(m[0xCC00:0xE000])+bytes(m[0x9840:0x9C00])).digest() if (len(S['segs'][-1])%8==0 and S['sync']>0) else b''
        S['segs'][-1].append((bytes(w)+bytes(h),lv)); S['total']+=1
        ly=m[0xFF44]; S['ly'][ly]=S['ly'].get(ly,0)+1
    pb.hook_register(0,0x0D3D,frame,None)
    n=0
    while S['total']<N and n<N*4+6000:
        pb.tick(1,False); n+=1
    S['ticks']=n; pb.stop(save=False); return S
A=run(A_ROM,False); B=run(B_ROM,not mono)
print("stage %d, series %d, %s: %d game frames; real frames original %d, DX %d (%+.2f %%)"%(stage,seed,'DX in monochrome' if mono else 'DX in color',N,A['ticks'],B['ticks'],100.0*(B['ticks']-A['ticks'])/A['ticks']))
ok=True
# Title animation variables (counters, scrolling): they depend on real time and keep their last value afterwards.
# They are only set aside if they actually differed during the title.
TITLE=set([0xB6,0xBD,0xBE,0x1A3,0x1A4,0x1A5,0x1A6,0x1A7,0x1A8,0xC00+0x3A,0xC00+0x3B,0xC00+0x3D])
seen=set()
def adr(i): return 0xC000+i if i<0xC00 else 0xFF80+i-0xC00
for k in range(max(len(A['segs']),len(B['segs']))):
    a=A['segs'][k] if k<len(A['segs']) else []; b=B['segs'][k] if k<len(B['segs']) else []
    n=min(len(a),len(b)); d=None; where=[]
    for i in range(n):
        if a[i][0]!=b[i][0]:
            idx=[j for j in range(len(a[i][0])) if a[i][0][j]!=b[i][0][j]]
            if k==0: seen|=set(idx)
            idx=[j for j in idx if not (j in TITLE and j in seen)]
            if idx and d is None: d=i; where=['%04X'%adr(j) for j in idx[:8]]
        if d is None and a[i][1]!=b[i][1]: d=i; where=['screen or level']
    name="before the 1st level (title, cutscene)" if k==0 else "level load #%d"%k
    if k==0:
        print("  %-40s: %5d frames compared, %s"%(name,n,"identical" if d is None else "differs at frame %d %s (cutscene pacing, not gameplay)"%(d,where)))
    else:
        if d is not None: ok=False
        print("  %-40s: %5d frames compared, %s"%(name,n,"IDENTICAL" if d is None else "DIFFERENT at frame %d %s"%(d,where)))
mx=lambda h: max(k for k in h if k>=144) if any(k>=144 for k in h) else 0
print("  last line reached by end-of-frame work: original %d, DX %d (limit 153)"%(mx(A['ly']),mx(B['ly'])))
print("  VERDICT:", "SAME GAME" if ok else "GAMEPLAY DIFFERS")
sys.exit(0 if ok else 1)
