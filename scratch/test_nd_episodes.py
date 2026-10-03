from bs4 import BeautifulSoup
import re

with open('scratch/got_page.html', 'r', encoding='utf-8') as f:
    pass

import urllib.request
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
    lhref = href.lower()
    isSupported = any(d in lhref for d in ['vcloud', 'fastdl', 'vegadrive', 'filebee'])
    if not isSupported:
        continue
    if any(d in lhref for d in ['telegram', 't.me', 'facebook', 'twitter', '.fans']):
        continue
    if href in seen_urls:
        continue
    seen_urls.add(href)
    
    # Preceding text/heading
    rawTitle = ''
    # Direct previous sibling
    sib = a.previous_sibling
    while sib:
        if hasattr(sib, 'get_text'):
            st = sib.get_text().strip()
            if any(k in st.lower() for k in ['episode', 'ep ', 'ep.']):
                rawTitle = st
                break
        sib = sib.previous_sibling
        
    # Parent's previous sibling
    if not rawTitle and a.parent:
        p_sib = a.parent.previous_sibling
        while p_sib:
            if hasattr(p_sib, 'get_text'):
                st = p_sib.get_text().strip()
                if any(k in st.lower() for k in ['episode', 'ep ', 'ep.']):
                    rawTitle = st
                    break
            p_sib = p_sib.previous_sibling
            
    episodes.append({
        'title': rawTitle,
        'url': href,
    })

print(f'Total extracted episodes: {len(episodes)}')
for i, ep in enumerate(episodes):
    print(f"[{i+1}] Title: '{ep['title']}' -> {ep['url']}")
