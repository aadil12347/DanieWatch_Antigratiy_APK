import urllib.request, re
from bs4 import BeautifulSoup

url = 'https://nexdrive.fit/genxfm784776336319/'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Referer': 'https://vegamovies.gallery/'})
with urllib.request.urlopen(req) as resp:
    html = resp.read().decode('utf-8', errors='ignore')

soup = BeautifulSoup(html, 'html.parser')
anchors = soup.find_all('a', href=True)

episodes = []
seen_urls = set()

for a in anchors:
    href = a['href']
    lh = href.lower()
    if not any(d in lh for d in ['vcloud', 'fastdl', 'vegadrive', 'filebee']):
        continue
    if any(d in lh for d in ['telegram', 't.me', 'facebook', 'twitter', '.fans']):
        continue
    if href in seen_urls:
        continue
    seen_urls.add(href)

    # find preceding text
    raw = ''
    sib = a.previous_sibling
    while sib:
        if hasattr(sib, 'get_text'):
            st = sib.get_text().strip()
            if any(k in st.lower() for k in ['episode', 'ep ', 'ep.']):
                raw = st
                break
        sib = sib.previous_sibling
    if not raw and a.parent:
        p_sib = a.parent.previous_sibling
        while p_sib:
            if hasattr(p_sib, 'get_text'):
                st = p_sib.get_text().strip()
                if any(k in st.lower() for k in ['episode', 'ep ', 'ep.']):
                    raw = st
                    break
            p_sib = p_sib.previous_sibling

    clean = re.sub(r'\s+', ' ', raw).strip()
    singleMatch = re.search(r'episode[s]?\s*[:\s]*0*(\d+)', clean, re.I)
    epNum = int(singleMatch.group(1)) if singleMatch else None

    print(f'Anchor: {clean} | epNum: {epNum} | href: {href}')
