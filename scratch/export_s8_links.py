import urllib.request, re, base64, json, sys, io
from bs4 import BeautifulSoup

headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36'}

def get(url, ref=None):
    h = dict(headers)
    if ref:
        h['Referer'] = ref
    req = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.read().decode('utf-8', errors='ignore')

def resolve_vcloud(url):
    html = get(url)
    s = BeautifulSoup(html, 'html.parser')
    inter = None
    for a in s.find_all('a', href=True):
        t = a.get_text().lower()
        if 'direct download' in t or 'resume' in t:
            inter = a['href'].strip()
            break
    ref = url
    if inter:
        html = get(inter, ref=url)
        ref = inter
    m2 = re.search(r'atob\(\s*atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)\s*\)', html)
    tok = base64.b64decode(base64.b64decode(m2.group(1)).decode()).decode() if m2 else None
    if not tok:
        return {}
    thtml = get(tok, ref=ref)
    ts = BeautifulSoup(thtml, 'html.parser')
    d = {}
    for a in ts.find_all('a', href=True):
        h, t, aid = a['href'], a.get_text().strip(), a.get('id', '')
        if '[fslv2 server]' in t.lower() or aid == 's3':
            d['FSLv2'] = h
        elif '[fsl server]' in t.lower() or aid == 'fsl':
            d['FSL'] = h
        elif '10gbps' in t.lower():
            d['10Gbps'] = h
        elif 'pixel' in t.lower():
            d['Pixeldrain'] = h
    return d

def resolve_fastdl(url):
    html = get(url, ref='https://fastdl.zip/')
    m = re.search(r'link=(https://video-downloads\.googleusercontent\.com/[^"\x27\s]+)', html)
    if m:
        return m.group(1)
    re_match = re.search(r'''var\s+reurl\s*=\s*['"]([^'"]+)['"]''', html)
    if re_match:
        return re_match.group(1)
    return None

nd_html = get('https://nexdrive.fit/genxfm784776336319/', ref='https://vegamovies.gallery/')
soup = BeautifulSoup(nd_html, 'html.parser')
eps = {}
for a in soup.find_all('a', href=True):
    h = a['href']
    if 'vcloud' not in h.lower() and 'fastdl' not in h.lower():
        continue
    raw = ''
    p = a.parent.previous_sibling
    while p and not raw:
        if hasattr(p, 'get_text') and 'episode' in p.get_text().lower():
            raw = p.get_text().strip()
        p = p.previous_sibling
    m = re.search(r'episode[s]?\s*[:\s]*0*(\d+)', re.sub(r'[-:~_*#]+', ' ', raw).strip(), re.I)
    n = int(m.group(1)) if m else len(eps)+1
    if n not in eps:
        eps[n] = {'vcloud': None, 'fastdl': None}
    if 'vcloud' in h.lower():
        eps[n]['vcloud'] = h
    elif 'fastdl' in h.lower():
        eps[n]['fastdl'] = h

results = {}
for n in sorted(eps.keys()):
    print(f"Resolving Episode {n}...")
    v_links = resolve_vcloud(eps[n]['vcloud']) if eps[n]['vcloud'] else {}
    f_link = resolve_fastdl(eps[n]['fastdl']) if eps[n]['fastdl'] else None
    results[n] = {
        'vcloud_page': eps[n]['vcloud'],
        'fastdl_page': eps[n]['fastdl'],
        'vcloud_streams': v_links,
        'fastdl_stream': f_link
    }

with open('scratch/s8_full_results.json', 'w', encoding='utf-8') as f:
    json.dump(results, f, indent=2)

print('SUCCESS')
