import urllib.request, re, base64, json, sys, io
from bs4 import BeautifulSoup

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
}

def fetch_html(url, referer=None):
    h = dict(headers)
    if referer:
        h['Referer'] = referer
    req = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.read().decode('utf-8', errors='ignore')

def resolve_vcloud(vcloud_url):
    print(f"    [VCloud Page] Fetching {vcloud_url} ...")
    v_html = fetch_html(vcloud_url)
    
    # Check intermediate
    token_url = None
    intermediate_url = None
    soup = BeautifulSoup(v_html, 'html.parser')
    for a in soup.find_all('a', href=True):
        href = a['href'].strip()
        text = a.get_text().strip().lower()
        lh = href.lower()
        if 'direct download' in text or 'resume' in text or 'vcloud.zip' in lh or ('vcloud' in lh and 'index.php' not in lh):
            intermediate_url = href
            break
            
    eff_ref = vcloud_url
    if intermediate_url:
        print(f"    [Intermediate] Following {intermediate_url} ...")
        inter_html = fetch_html(intermediate_url, referer=vcloud_url)
        eff_ref = intermediate_url
        v_html = inter_html

    # double atob
    m2 = re.search(r'atob\(\s*atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)\s*\)', v_html)
    if m2:
        s1 = base64.b64decode(m2.group(1)).decode('utf-8')
        token_url = base64.b64decode(s1).decode('utf-8')
    else:
        m1 = re.search(r'atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)', v_html)
        if m1:
            token_url = base64.b64decode(m1.group(1)).decode('utf-8')
            
    if not token_url:
        m_var = re.search(r'''(?:location\.href|window\.location|var\s+url)\s*=\s*['"]([^'"]+)['"]''', v_html, re.I)
        if m_var:
            token_url = m_var.group(1)

    if not token_url:
        return {"error": "Could not extract token URL"}

    print(f"    [Token Page] Fetching {token_url} ...")
    tok_html = fetch_html(token_url, referer=eff_ref)
    tok_soup = BeautifulSoup(tok_html, 'html.parser')
    
    res = {}
    for a in tok_soup.find_all('a', href=True):
        href = a['href']
        text = a.get_text().strip()
        lt = text.lower()
        lh = href.lower()
        aid = a.get('id', '')
        
        if '[fslv2 server]' in lt or aid == 's3' or 'r2.cloudflarestorage.com' in lh or 'fslv2' in lh:
            res['FSLv2'] = href
        elif '[fsl server]' in lt or aid == 'fsl' or ('fsl' in lh and 'fslv2' not in lh):
            res['FSL'] = href
        elif '10gbps' in lt or 'g-direct' in lt or 'pixel.hubcloud' in lh:
            res['10Gbps'] = href
        elif 'pixel' in lt or 'pixeldrain' in lh:
            res['Pixeldrain'] = href
            
    return res

def resolve_fastdl(fastdl_url):
    print(f"    [FastDL] Fetching {fastdl_url} ...")
    f_html = fetch_html(fastdl_url, referer='https://fastdl.zip/')
    g_match = re.search(r'link=(https://video-downloads\.googleusercontent\.com/[^"\x27\s]+)', f_html)
    if g_match:
        return g_match.group(1)
    re_match = re.search(r'''var\s+reurl\s*=\s*['"]([^'"]+)['"]''', f_html)
    if re_match:
        return re_match.group(1)
    return None

# Step 1: Fetch GOT S8 Nextdrive page
nd_url = 'https://nexdrive.fit/genxfm784776336319/'
print(f"Step 1: Fetching Season 8 Nextdrive selector page: {nd_url}")
nd_html = fetch_html(nd_url, referer='https://vegamovies.gallery/')
soup = BeautifulSoup(nd_html, 'html.parser')

episodes = {} # ep_num -> {'title': ..., 'vcloud': ..., 'fastdl': ...}

for a in soup.find_all('a', href=True):
    href = a['href']
    if 'vcloud' not in href.lower() and 'fastdl' not in href.lower():
        continue
    # find heading
    raw = ''
    psib = a.parent.previous_sibling
    while psib and not raw:
        if hasattr(psib, 'get_text') and 'episode' in psib.get_text().lower():
            raw = psib.get_text().strip()
        psib = psib.previous_sibling
    
    clean = re.sub(r'[-:~_*#]+', ' ', raw).strip()
    m = re.search(r'episode[s]?\s*[:\s]*0*(\d+)', clean, re.I)
    ep_num = int(m.group(1)) if m else len(episodes) + 1
    
    if ep_num not in episodes:
        episodes[ep_num] = {'title': f"Episode {ep_num}", 'vcloud': None, 'fastdl': None}
        
    if 'vcloud' in href.lower():
        episodes[ep_num]['vcloud'] = href
    elif 'fastdl' in href.lower():
        episodes[ep_num]['fastdl'] = href

print(f"\nStep 2: Found {len(episodes)} episodes.")
for num in sorted(episodes.keys()):
    ep = episodes[num]
    print(f"\n==========================================")
    print(f"Season 8 - {ep['title']}")
    print(f"VCloud URL (Primary):  {ep['vcloud']}")
    print(f"FastDL URL (Fallback): {ep['fastdl']}")
    print(f"Resolving direct stream links...")
    
    # 1. Resolve VCloud
    if ep['vcloud']:
        try:
            v_res = resolve_vcloud(ep['vcloud'])
            print(f"  --> Direct Links from VCloud:")
            for k, v in v_res.items():
                print(f"      [{k}]: {v[:90]}...")
        except Exception as e:
            print(f"  --> VCloud error: {e}")
            
    # 2. Resolve FastDL
    if ep['fastdl']:
        try:
            f_res = resolve_fastdl(ep['fastdl'])
            print(f"  --> Direct Link from FastDL:")
            print(f"      [FastDL / GoogleUserContent]: {str(f_res)[:90]}...")
        except Exception as e:
            print(f"  --> FastDL error: {e}")
