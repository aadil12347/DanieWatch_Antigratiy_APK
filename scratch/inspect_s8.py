import urllib.request, re

url = 'https://vegamovies.gallery/download-game-of-thrones-season-1-8-hindi-dubbed-org-480p-720p-1080p-bluray/'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode('utf-8', errors='ignore')
    
    with open('scratch/got_page.html', 'w', encoding='utf-8') as f:
        f.write(html)
    print('Saved got_page.html, size:', len(html))

    # Find buttons with Season 8
    # Search for all links with 'G Direct' or 'Instant' or 'V-Cloud' or 'HubCloud' or 'NextDrive'
    links = re.findall(r'<a\s+[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', html, re.I | re.S)
    print(f'Total links: {len(links)}')
    
    s8_links = []
    for href, text in links:
        clean_text = re.sub(r'<[^>]+>', '', text).strip()
        if 'Season 8' in clean_text or 'S08' in clean_text or 'S8' in clean_text or 'Direct' in clean_text or 'Instant' in clean_text or 'Next' in clean_text or 'V-Cloud' in clean_text:
            s8_links.append((clean_text, href))
            
    print(f'Matching links: {len(s8_links)}')
    for t, h in s8_links[:30]:
        print(f'Text: {t[:60]} -> {h}')
except Exception as e:
    print('Error:', e)
