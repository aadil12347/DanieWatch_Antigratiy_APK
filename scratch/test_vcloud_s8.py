import urllib.request, re, sys, io, base64

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

# Test the vcloud.fit URL for Episode 1 of S8 720p
url = 'https://vcloud.fit/zwo5kbpl7rt_t5l'
headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
}
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode('utf-8', errors='ignore')
    print(f'VCloud page size: {len(html)}')
    with open('scratch/s8_ep1_vcloud.html', 'w', encoding='utf-8') as f:
        f.write(html)
    
    # Check for double atob
    atob2 = re.search(r"atob\(\s*atob\(\s*[\"']([^\"']+)[\"']\s*\)\s*\)", html)
    if atob2:
        s1 = base64.b64decode(atob2.group(1)).decode('utf-8')
        tokenUrl = base64.b64decode(s1).decode('utf-8')
        print(f'Double atob decoded tokenUrl: {tokenUrl}')
    else:
        print('No double atob found')
    
    # Check for single atob
    atob1 = re.search(r"atob\(\s*[\"']([^\"']+)[\"']\s*\)", html)
    if atob1:
        s1 = base64.b64decode(atob1.group(1)).decode('utf-8')
        print(f'Single atob decoded: {s1}')
    else:
        print('No single atob found')
    
    # Check for var url
    varUrl = re.search(r"(?:location\.href|window\.location|var\s+url)\s*=\s*[\"']([^\"']+)[\"']", html, re.I)
    if varUrl:
        print(f'var url/location.href: {varUrl.group(1)}')
    else:
        print('No var url found')
    
    # Check for pxl
    pxl = re.search(r"var\s+pxl\s*=\s*[\"']([^\"']+)[\"']", html, re.I)
    if pxl:
        print(f'pxl URL: {pxl.group(1)}')
    else:
        print('No pxl found')
    
    # Show relevant JS snippets
    scripts = re.findall(r'<script[^>]*>(.*?)</script>', html, re.I | re.S)
    for i, s in enumerate(scripts):
        if len(s.strip()) > 10 and len(s) < 5000:
            if any(kw in s.lower() for kw in ['atob', 'url', 'location', 'token', 'redirect', 'download']):
                print(f'\nScript #{i} ({len(s)} chars):')
                print(s[:500])
                if len(s) > 500:
                    print('...')
    
    # Check for id='size'
    size_match = re.search(r"id=[\"']size[\"'][^>]*>([^<]+)<", html, re.I)
    if size_match:
        print(f'\nFile size: {size_match.group(1).strip()}')
        
except Exception as e:
    print(f'Error: {e}')
    import traceback
    traceback.print_exc()
