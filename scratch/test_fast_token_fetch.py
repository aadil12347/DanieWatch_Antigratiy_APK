import urllib.request, re, time, base64

v_url = 'https://vcloud.fit/zwo5kbpl7rt_t5l'
headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}

# 1. Fast fetch VCloud token
t0 = time.time()
resp = urllib.request.urlopen(urllib.request.Request(v_url, headers=headers))
html_v = ''
while True:
    chunk = resp.read(4096)
    if not chunk: break
    html_v += chunk.decode('utf-8', errors='ignore')
    if 'atob(atob(' in html_v and 'id="size"' in html_v:
        break
resp.close()

m2 = re.search(r'atob\(\s*atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)\s*\)', html_v)
token_url = base64.b64decode(base64.b64decode(m2.group(1)).decode()).decode()
print(f"Step 1 (Token URL + Size) took {time.time()-t0:.3f}s")

# 2. Fast fetch Token page
t1 = time.time()
req2 = urllib.request.Request(token_url, headers={'User-Agent': 'Mozilla/5.0', 'Referer': v_url})
resp2 = urllib.request.urlopen(req2)
html_t = ''
while True:
    chunk = resp2.read(4096)
    if not chunk: break
    html_t += chunk.decode('utf-8', errors='ignore')
    if ('[FSLv2 Server]' in html_t or 'id="s3"' in html_t) and ('[FSL Server]' in html_t or 'id="fsl"' in html_t):
        print(f"Step 2: Found all direct server links after reading only {len(html_t)} bytes in {time.time()-t1:.3f}s!")
        break
resp2.close()

print(f"===> TOTAL TIME FOR DIRECT LINKS: {time.time()-t0:.3f}s!")
