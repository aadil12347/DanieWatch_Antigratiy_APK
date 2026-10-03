import urllib.request, re, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

# Season 8 720p G-Direct link
url = 'https://nexdrive.fit/genxfm784776336319/'

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
}

req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode('utf-8', errors='ignore')
    
    with open('scratch/s8_720p_landing.html', 'w', encoding='utf-8') as f:
        f.write(html)
    print(f'Saved s8_720p_landing.html, size: {len(html)}')
    
    # Find all links on this page
    links = re.findall(r'<a\s+[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', html, re.I | re.S)
    print(f'\nTotal links: {len(links)}')
    
    for href, text in links:
        clean_text = re.sub(r'<[^>]+>', '', text).strip()
        lh = href.lower()
        if any(kw in lh for kw in ['vcloud', 'hubcloud', 'fastdl', 'vegadrive', 'filebee', 'pixeldrain']):
            print(f'  SUPPORTED: [{clean_text[:60]}] -> {href}')
        elif 'nexdrive' in lh:
            print(f'  NEXDRIVE: [{clean_text[:60]}] -> {href}')
        elif not any(skip in lh for kw in ['css', 'js', 'font'] for skip in [kw]):
            if clean_text and not lh.startswith('#') and not lh.startswith('javascript'):
                print(f'  OTHER: [{clean_text[:60]}] -> {href[:80]}')
    
    # Check for episode headings
    print('\n=== HEADINGS ===')
    headings = re.findall(r'<(h[1-6])[^>]*>(.*?)</\1>', html, re.I | re.S)
    for tag, content in headings:
        clean = re.sub(r'<[^>]+>', '', content).strip()
        if clean:
            print(f'  <{tag}>: {clean[:120]}')

    # Check for "Episode" mentions
    print('\n=== EPISODE MENTIONS ===')
    for m in re.finditer(r'[Ee]pisode\s*[:\s]*\d+', html):
        context = html[max(0,m.start()-30):m.end()+30]
        clean = re.sub(r'<[^>]+>', ' ', context).strip()[:80]
        print(f'  {clean}')
        
except Exception as e:
    print(f'Error: {e}')
    import traceback
    traceback.print_exc()
