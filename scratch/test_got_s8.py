from bs4 import BeautifulSoup
import re

with open('scratch/got_page.html', 'r', encoding='utf-8') as f:
    html = f.read()

soup = BeautifulSoup(html, 'html.parser')
content_el = soup.select_one('main.page-body, .page-body, .entry-content, #main-content, article') or soup.body

anchors = content_el.find_all('a', href=True)
print(f'Total anchors: {len(anchors)}')

buttons = []
for a in anchors:
    href = a['href']
    lh = href.lower()
    isLanding = any(d in lh for d in ['nexdrive', 'vgmlink', 'gdflix', 'fastdl', 'filebee', 'hubcloud', 'vcloud', 'pixeldrain'])
    if not isLanding:
        continue
    if any(d in lh for d in ['telegram', 'facebook', 'twitter', 'category/', '/tag/']):
        continue
        
    aText = re.sub(r'\s+', ' ', a.get_text().strip())
    lowerText = aText.lower()
    
    # Season & Quality upward search
    quality = '720p'
    seasonNumber = 1
    foundQuality = False
    foundSeason = False
    
    curr = a.parent
    while curr and curr != content_el and (not foundQuality or not foundSeason):
        sib = curr.previous_sibling
        while sib and (not foundQuality or not foundSeason):
            if hasattr(sib, 'get_text'):
                st = re.sub(r'\s+', ' ', sib.get_text()).strip()
                lowerSt = st.lower()
                tag = getattr(sib, 'name', '') or ''
                
                if not foundQuality and (re.match(r'^h[1-6]$', tag) or any(k in lowerSt for k in ['web-dl', 'bluray', 'hevc', '480p', '720p', '1080p'])):
                    if '2160p' in lowerSt or '4k' in lowerSt:
                        quality = '2160p'
                        foundQuality = True
                    elif '1080p' in lowerSt:
                        quality = '1080p'
                        foundQuality = True
                    elif '720p' in lowerSt:
                        quality = '720p'
                        foundQuality = True
                    elif '480p' in lowerSt:
                        quality = '480p'
                        foundQuality = True
                
                if not foundSeason:
                    sMatch = re.search(r'(?:Season|S)\s*0*(\d+)', st, re.I)
                    if sMatch:
                        s = int(sMatch.group(1))
                        if 0 < s < 100:
                            seasonNumber = s
                            foundSeason = True
            sib = sib.previous_sibling
        curr = curr.parent
        
    buttons.append({
        'text': aText,
        'href': href,
        'quality': quality,
        'season': seasonNumber,
    })

print(f'Extracted {len(buttons)} buttons')
s8_buttons = [b for b in buttons if b['season'] == 8]
print(f'Season 8 buttons: {len(s8_buttons)}')
for b in s8_buttons:
    print(f"S{b['season']} | {b['quality']} | Text: {b['text']} | URL: {b['href']}")
