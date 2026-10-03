import urllib.request, re

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://vegamovies.gallery/',
}

for url in ['https://nexdrive.fit/genxfm784776336319/', 'https://nexdrive.fit/genxfm784776336313/']:
    print('Testing URL:', url)
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            html = resp.read().decode('utf-8', errors='ignore')
        print('  Fetched length:', len(html))
        # Find all anchors
        anchors = re.findall(r'<a\s+[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', html, re.I | re.S)
        print('  Total links in page:', len(anchors))
        for h, t in anchors:
            ct = re.sub(r'<[^>]+>', '', t).strip()
            print('   -> Text:', ct.encode('ascii', 'ignore').decode(), '| URL:', h)
    except Exception as e:
        print('  Error:', e)
