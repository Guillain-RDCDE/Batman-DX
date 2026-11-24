# End-to-end test of the lab page docs/index.html.
# Needs: playwright, the original ROM, and the six games built into out/ by build.sh.
#   python3 -m http.server 8766 --directory docs &   then   python3 tools/test_page.py path/to/original.gb
import asyncio,hashlib,sys,os,json,tempfile
from playwright.async_api import async_playwright
ROM=sys.argv[1]; URL='http://localhost:8766/index.html'; ok=True
MOODS=('dx','plus','movie','comic','pastel','night','green')
def check(name,cond,detail=''):
    global ok; ok&=bool(cond); print(('OK   ' if cond else 'FAIL '),name,detail)
async def dl(pg,sel):
    async with pg.expect_download() as d: await pg.click(sel)
    v=await d.value; return open(await v.path(),'rb').read(),v.suggested_filename
sha=lambda b: hashlib.sha1(b).hexdigest()
def ips_apply(src,ips):
    d=bytearray(src); p=5
    while ips[p:p+3]!=b'EOF' or p+3!=len(ips):
        o=int.from_bytes(ips[p:p+3],'big'); n=int.from_bytes(ips[p+3:p+5],'big'); p+=5
        if n: d[o:o+n]=ips[p:p+n]; p+=n
        else:
            r=int.from_bytes(ips[p:p+2],'big'); d[o:o+r]=bytes([ips[p+2]])*r; p+=3
    return bytes(d)
async def main():
    orig=open(ROM,'rb').read()
    async with async_playwright() as p:
        b=await p.chromium.launch(); ctx=await b.new_context(accept_downloads=True,locale='en-US'); pg=await ctx.new_page()
        errs=[]; pg.on('pageerror',lambda e: errs.append(str(e)))
        await pg.goto(URL)
        open('/tmp/fake.gb','wb').write(os.urandom(131072)); await pg.set_input_files('#f','/tmp/fake.gb'); await pg.wait_for_timeout(500)
        check('random file rejected','not the expected' in await pg.inner_text('#status')); check('nothing unlocked',await pg.is_hidden('#c2'))
        await pg.set_input_files('#f','out/Batman-DX-dx.gbc'); await pg.wait_for_timeout(500)
        check('already patched ROM rejected','already' in await pg.inner_text('#status'))
        await pg.set_input_files('#f',ROM); await pg.wait_for_selector('#c2:not([hidden])'); await pg.wait_for_timeout(1500)
        check('original ROM accepted','right one' in await pg.inner_text('#status'))
        for v in MOODS:
            await pg.select_option('#mood',v); await pg.wait_for_timeout(1200)
            data,name=await dl(pg,'#dlrom'); want=open('out/Batman-DX-%s.gbc'%v,'rb').read()
            check('mood %-6s: game identical to the build'%v,data==want,name+' '+sha(data)[:12])
            check('mood %-6s: checksum displayed'%v,sha(want) in await pg.inner_text('#sha'))
            ips,iname=await dl(pg,'#dlips'); ref=open('patches/Batman-DX%s.ips'%('' if v=='dx' else '-'+v),'rb').read()
            check('mood %-6s: downloaded patch = repository patch, and gives the game'%v,ips==ref and ips_apply(orig,ips)==want,iname)
        await pg.select_option('#mood','plus'); await pg.wait_for_timeout(1500)
        check('Plus edition: editor hidden, note shown',await pg.is_hidden('#c4') and '256' in await pg.inner_text('#moodnote'))
        await pg.select_option('#mood','dx'); await pg.wait_for_timeout(1200)
        await pg.select_option('#scene','2'); await pg.select_option('#what','bg')
        await pg.evaluate("()=>{const i=document.querySelector('#pals input');i.value='#ff0000';i.dispatchEvent(new Event('input'))}")
        await pg.click('#tryit'); await pg.wait_for_timeout(1500)
        data,name=await dl(pg,'#dlrom'); want=open('out/Batman-DX-dx.gbc','rb').read()
        diff=[i for i in range(len(want)) if want[i]!=data[i]]
        t=0x18D47+4; adr=0x18000+((want[t]|want[t+1]<<8)-0x4000)+256
        check('lab: only the color and the checksum change',set(diff)<= {adr,adr+1,0x14E,0x14F} and adr in diff,str(['%X'%i for i in diff])+' '+name)
        check('lab: color written = pure red',data[adr]|(data[adr+1]<<8)==31)
        s=sum(data[i] for i in range(len(data)) if i not in (0x14E,0x14F))&0xFFFF
        check('lab: global checksum correct',data[0x14E]==s>>8 and data[0x14F]==s&255)
        ips,_=await dl(pg,'#dlips'); check('lab: the custom patch gives the custom game',ips_apply(orig,ips)==data)
        j,_=await dl(pg,'#exportbtn'); J=json.loads(j); check('export: 16 scenes, red present',len(J['scenes'])==16 and J['scenes'][2]['bg'][0][0]==[31,0,0])
        await pg.click('#reset'); await pg.wait_for_timeout(1200); d2,_=await dl(pg,'#dlrom'); check('back to the mood: the mood game again',d2==want)
        open('/tmp/colors.json','wb').write(j); await pg.set_input_files('#importfile','/tmp/colors.json'); await pg.wait_for_timeout(1500)
        d3,_=await dl(pg,'#dlrom'); check('import: gives exactly the custom game',d3==data)
        await pg.click('#reset'); await pg.wait_for_timeout(9000)
        px=await pg.evaluate("()=>{const c=document.getElementById('lcd');const d=c.getContext('2d').getImageData(0,0,160,144).data;let n=0;for(let i=0;i<d.length;i+=4)if(d[i]+d[i+1]+d[i+2]>60)n++;return n}")
        check('emulator: picture is not black',px>300,'%d bright dots'%px)
        check('English by default',(await pg.inner_text('h2')).strip().upper()=='ORIGINAL ROM')
        await pg.click('#bfr'); check('French on request',(await pg.inner_text('h2')).strip().upper().startswith('ROM D'))
        check('no JavaScript error',not errs,str(errs[:2])); await b.close()
    print('RESULT:','ALL GOOD' if ok else 'THERE ARE FAILURES'); sys.exit(0 if ok else 1)
asyncio.run(main())
