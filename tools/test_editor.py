# Test of the editor in the lab page (preview, palette per tile, transparent edges).
# Needs: playwright, pyboy, the original ROM, and out/Batman-DX-dx.gbc built by build.sh.
#   python3 -m http.server 8766 --directory docs &   then   python3 tools/test_editor.py path/to/original.gb
import asyncio,hashlib,sys,os,json,tempfile
from playwright.async_api import async_playwright
ROM=sys.argv[1]; URL='http://localhost:8766/index.html'; ok=True
MOODS=('dx','movie','comic','pastel','night','green')
def check(name,cond,detail=''):
    global ok; ok&=bool(cond); print(('OK   ' if cond else 'FAIL '),name,detail)
async def dl(pg,sel):
    async with pg.expect_download() as d: await pg.click(sel)
    v=await d.value; return open(await v.path(),'rb').read(),v.suggested_filename
D=open(ROM,'rb').read()
def level_ref(mapid):                      # same reading as routine $10D5, written separately to cross-check the page
    o=7*0x4000+mapid*4; mb=7*0x4000+(D[o]|D[o+1]<<8)-0x4000; p=7*0x4000+(D[o+2]|D[o+3]<<8)-0x4000; ram=bytearray(20*256)
    for page in range(20):
        e=0
        for l in range(8):
            c=D[p]; p+=1
            for k in range(8):
                a=D[p]
                if c&0x80: p+=1
                c=(c<<1)&255; t=D[mb+a*4:mb+a*4+4]; b=page*256
                ram[b+e]=t[0]; ram[b+(e|0x10)]=t[1]; ram[b+((e+1)&255)]=t[2]; ram[b+(((e+1)&255)|0x10)]=t[3]; e=(e+0x20)&255
            e=(e+2)&255
    return bytes(ram)
def scenes_ref(d):
    out=[]
    for i in range(16):
        p=0x18D47+2*i; o=0x18000+((d[p]|d[p+1]<<8)-0x4000); tab=d[o:o+256]; o+=256+128+1; recs={}
        while d[o]: n=d[o]; recs[d[o+1]|d[o+2]<<8]=bytes(d[o+3:o+3+n]); o+=3+n
        out.append(dict(tab=tab,recs=recs,end=o))
    return out
def emulate(rom,stage,frames):             # runs the produced game up to the level; returns video memory, the table in RAM, the mode
    from pyboy import PyBoy
    f=tempfile.NamedTemporaryFile(suffix='.gbc',delete=False); f.write(rom); f.close()
    pb=PyBoy(f.name,window='null',cgb=True,sound_emulated=False); r=pb.register_file; m=pb.memory
    pb.hook_register(0,0x0477,lambda c: setattr(r,'A',stage),None)
    for i in range(frames):
        if i==1500: pb.button('start',4)
        pb.tick(1,False)
    m[0xFF4F]=0; v=bytes(m[0x8000:0x9800]); tab=bytes(m[0xC600:0xC700]); mode=m[0xFF9A]; pb.stop(save=False); os.unlink(f.name); return v,tab,mode
inzones=lambda S: all(0x18D67<=s['end']<0x1A800 or 0x1B636<=s['end']<0x1C000 for s in S)
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(); ctx=await b.new_context(accept_downloads=True,locale='en-US',viewport={'width':1200,'height':1400}); pg=await ctx.new_page()
        errs=[]; pg.on('pageerror',lambda e: errs.append(str(e)))
        await pg.goto(URL); await pg.set_input_files('#f',ROM); await pg.wait_for_selector('#c4:not([hidden])'); await pg.wait_for_timeout(1500)
        for mid in (1,2,3,4,5,6,7,8,9,0x0B,0x0C):
            h=await pg.evaluate("(i)=>Array.from(level(i))",mid)
            check('level %02X read by the page = reference reading'%mid,bytes(h)==level_ref(mid))
        vo,_,_=emulate(D,6,2600)
        vj=bytes(await pg.evaluate("()=>Array.from(originalVideo(5))"))
        check('museum drawings read by the page = video memory of the original game',vj[0x800:0x1800]==vo[0x800:0x1800])
        vis=[]
        for s in range(16):
            await pg.select_option('#scene',str(s)); await pg.wait_for_timeout(120); vis.append(not await pg.is_hidden('#view'))
        check('preview: levels and cutscenes only',vis==[False,False]+[True]*13+[False],str(vis))
        await pg.select_option('#scene','5'); await pg.wait_for_timeout(300)
        pos=await pg.evaluate("()=>{const k=tilemap(5);const i=k.c.indexOf(0x64);return [i%k.w,Math.floor(i/k.w)]}")
        await pg.locator('.scroller').evaluate("(e,x)=>{e.scrollLeft=Math.max(0,x-200)}",pos[0]*16)
        await pg.locator('.scroller').scroll_into_view_if_needed(); await pg.wait_for_timeout(200)
        box=await pg.locator('#preview').bounding_box()
        await pg.mouse.click(box['x']+pos[0]*16+8,box['y']+pos[1]*16+8); await pg.wait_for_timeout(300)
        check('click on the preview: the right tile is picked',await pg.evaluate("()=>picked")==0x64,await pg.inner_text('#tiletitle'))
        await pg.select_option('#tilepal','4'); await pg.click('#detect'); await pg.select_option('#inside','1'); await pg.click('#apply'); await pg.wait_for_timeout(300)
        att=await pg.evaluate("()=>{const o=pixels(originalVideo(5),0x64),px=[];for(let i=0;i<64;i++)px.push(mask[i]?0:INSIDE[1][o[i]]);return [encode(px),Array.from(mask).reduce((a,b)=>a+b,0),Array.from(o).filter(v=>v===0).length]}")
        check('retouch: detected background only takes light dots',0<=att[1]<=att[2],'%d background dots out of %d light ones'%(att[1],att[2]))
        rom,_=await dl(pg,'#dlrom'); base=open('out/Batman-DX-dx.gbc','rb').read(); S=scenes_ref(rom); S0=scenes_ref(base)
        adr=0x9000+0x64*16
        check('produced ROM: the retouch is recorded in the museum scene',S[5]['recs'].get(adr)==bytes(att[0]))
        check('produced ROM: the palette of that tile changed, and only that one',S[5]['tab'][0x64]==4 and sum(1 for i in range(256) if S[5]['tab'][i]!=S0[5]['tab'][i])<=1)
        check('produced ROM: the other scenes are untouched',all(S[i]['tab']==S0[i]['tab'] and S[i]['recs']==S0[i]['recs'] for i in range(16) if i!=5))
        check('produced ROM: every scene fits in its area',inzones(S))
        s=sum(rom[i] for i in range(len(rom)) if i not in (0x14E,0x14F))&0xFFFF
        check('produced ROM: checksum correct',rom[0x14E]==s>>8 and rom[0x14F]==s&255)
        v,tab,mode=emulate(rom,6,2600)
        check('in game: the museum level is loaded',mode&0x80)
        check('in game: the retouched tile is in video memory',v[adr-0x8000:adr-0x8000+16]==bytes(att[0]))
        check('in game: the table in RAM gives palette 4 to that tile',tab[0x64]==4)
        await pg.click('#remove'); await pg.select_option('#tilepal',str(S0[5]['tab'][0x64])); await pg.wait_for_timeout(200)
        check('removing the retouch: exactly the starting game again',(await dl(pg,'#dlrom'))[0]==base)
        await pg.select_option('#tilepal','4'); await pg.click('#detect'); await pg.click('#apply'); await pg.wait_for_timeout(200)
        r1,_=await dl(pg,'#dlrom'); j,_=await dl(pg,'#exportbtn'); open('/tmp/settings.json','wb').write(j)
        await pg.click('#reset'); await pg.wait_for_timeout(1200); check('back to the mood',(await dl(pg,'#dlrom'))[0]==base)
        await pg.set_input_files('#importfile','/tmp/settings.json'); await pg.wait_for_timeout(1500)
        check('export then import: same game, retouch included',(await dl(pg,'#dlrom'))[0]==r1)
        await pg.click('#reset'); await pg.wait_for_timeout(1200)
        n=await pg.evaluate("()=>{let n=0; for(let t=0x40;t<0xA0;t++){ M[2].recs.push({addr:tileAddr(t),data:new Array(16).fill(0)}); if(!rebuild()){M[2].recs.pop();rebuild();break} n++ } return n}")
        check('room: the page stops by itself when the cartridge is full',0<n<96,'%d retouches added before refusing'%n)
        rp,_=await dl(pg,'#dlrom'); Sp=scenes_ref(rp)
        check('room: the game produced at the limit is well formed',inzones(Sp) and len(Sp[2]['recs'])>=n)
        v,tab,mode=emulate(rp,1,3300)
        check('room: the game produced at the limit boots and loads Gotham',mode&0x80 and tab==bytes(Sp[2]['tab']))
        check('no JavaScript error',not errs,str(errs[:2])); await b.close()
    print('RESULT:','ALL GOOD' if ok else 'THERE ARE FAILURES'); sys.exit(0 if ok else 1)
asyncio.run(main())
