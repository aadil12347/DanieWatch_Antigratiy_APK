import urllib.request, re, sys, io, base64

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

# Token URL decoded from double atob
token_url = 'https://vcloud.fit/zwo5kbpl7rt_t5l?token=dzhjeHVCQVdEdDVFLzh5T1dhNk10aEpsTVBxNXBTYVhKa1JuTm4wenZZQT0='
referer = 'https://vcloud.fit/zwo5kbpl7rt_t5l'

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Referer': referer,
}
req = urllib.request.Request(token_url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode('utf-8', errors='ignore')
    print(f'Token page size: {len(html)}')
    with open('scratch/s8_ep1_token.html', 'w', encoding='utf-8') as f:
        f.write(html)
    
    # Find server links
    links = re.findall(r'<a\s+[^>]*href="([^"]+)"[^>]*>(.*?)</a>', html, re.I | re.S)
    print(f'\nTotal links: {len(links)}')
    for href, text in links:
        clean_text = re.sub(r'<[^>]+>', '', text).strip()
        lh = href.lower()
        # Skip obvious non-download links
        if any(skip in lh for skip in ['css', 'fonts', 'favicon', 'telegram', 't.me', 'google.com', 'admin']):
            continue
        if clean_text or 'token=' in lh:
            # Check for id attribute
            id_match = re.search(r'id="([^"]*)"', text + ' ' + re.search(r'<a\s+([^>]+)', html[html.find(href)-200:html.find(href)+len(href)+10] if html.find(href) > 0 else '').group(1) if re.search(r'<a\s+([^>]+)', html[max(0,html.find(href)-200):html.find(href)+len(href)+10]) else '', re.I)
            print(f'  [{clean_text[:60]}] -> {href[:120]}')
    
    # Check for pxl
    pxl = re.search(r"var\s+pxl\s*=\s*[\"']([^\"']+)[\"']", html, re.I)
    if pxl:
        print(f'\npxl URL: {pxl.group(1)}')
    
    # Check for FSL/FSLv2 mentions
    if 'fsl' in html.lower():
        print('\nPage contains "fsl" references')
    if 'server' in html.lower():
        print('Page contains "server" references')
    if 'pixeldrain' in html.lower():
        print('Page contains "pixeldrain" references')
    if '10gbps' in html.lower() or '10Gbps' in html:
        print('Page contains "10Gbps" references')
        
    # Show id attributes of links
    print('\n=== Link ID attributes ===')
    for m in re.finditer(r'<a\s+([^>]*id="([^"]*)"[^>]*)href="([^"]+)"', html, re.I):
        attrs = m.group(1)
        link_id = m.group(2)
        href = m.group(3)
        print(f'  id="{link_id}" -> {href[:100]}')
    
    # Try alternate pattern
    for m in re.finditer(r'<a\s+href="([^"]+)"([^>]*)>', html, re.I):
        href = m.group(1)
        rest = m.group(2)
        id_m = re.search(r'id="([^"]*)"', rest)
        if id_m:
            print(f'  id="{id_m.group(1)}" -> {href[:100]}')

except Exception as e:
    print(f'Error: {e}')
    import traceback
    traceback.print_exc()
