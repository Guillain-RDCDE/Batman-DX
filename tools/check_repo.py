# Repository checks (no ROM needed): well-formed patches, complete colors, links and images present, no game file.
import glob,json,os,re,sys,py_compile,subprocess
ok=True
def bad(m):
    global ok; ok=False; print("FAIL:",m)
# 1. no game in the repository
for f in subprocess.run(['git','ls-files'],capture_output=True,text=True).stdout.split('\n'):
    if f.lower().endswith(('.gb','.gbc','.sav')): bad("game file present: "+f)
# 2. well-formed IPS patches that only write inside a 128 KB cartridge (256 KB for the Plus edition)
ips=sorted(glob.glob('patches/*.ips'))
if len(ips)!=7: bad("7 patches expected, found %d"%len(ips))
for f in ips:
    d=open(f,'rb').read()
    if d[:5]!=b'PATCH' or d[-3:]!=b'EOF': bad(f+": header or end"); continue
    p=5
    while p<len(d)-3:
        o=int.from_bytes(d[p:p+3],'big'); l=int.from_bytes(d[p+3:p+5],'big'); p+=5
        if l==0: l=int.from_bytes(d[p:p+2],'big'); p+=3
        else: p+=l
        if o+l>(262144 if f.endswith("-plus.ips") else 131072): bad(f+": writes outside the cartridge")
    if p!=len(d)-3: bad(f+": structure")
    if open('docs/'+f,'rb').read()!=d: bad(f+": the copy in docs/ differs")
# 3. colors: 16 complete scenes per mood
for f in sorted(glob.glob('src/moods/*.json')):
    S=json.load(open(f))['scenes']
    if len(S)!=16: bad(f+": %d scenes"%len(S))
    for n,s in S.items():
        if len(s['tab'])!=256 or any(not 0<=t<(16 if f.endswith('plus.json') else 8) for t in s['tab']): bad(f+" "+n+": table")
        for q in ('bg','obj'):
            for p in (s[q] or []):
                if p and (len(p)!=4 or any(not 0<=v<32 for c in p for v in c)): bad(f+" "+n+": palette")
# 4. links and images of the pages
for md in glob.glob('*.md'):
    t=open(md,encoding='utf-8').read()
    for m in re.finditer(r'(?:\]\(|src=")([^)"#]+)',t):
        u=m.group(1)
        if not u.startswith('http') and not os.path.exists(u): bad(md+": dead link "+u)
# 5. the Python code compiles
for f in glob.glob('tools/*.py'):
    try: py_compile.compile(f,doraise=True)
    except Exception as e: bad(f+": "+str(e)[:80])
print("RESULT:","all good" if ok else "there are failures"); sys.exit(0 if ok else 1)
