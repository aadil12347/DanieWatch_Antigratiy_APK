import urllib.request
import re

urls = [
    ('480p', 'https://vcloud.fit/uvkiz9ngoghgu97'),
    ('720p', 'https://vcloud.fit/zwo5kbpl7rt_t5l'),
    ('1080p', 'https://vcloud.fit/mioupoup8usuikw')
]

for q, u in urls:
    req = urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        html = urllib.request.urlopen(req, timeout=10).read().decode('utf-8')
        m = re.search(r'id=["\']size["\'][^>]*>([^<]+)<', html, re.I)
        size = m.group(1).strip() if m else 'NOT FOUND'
        print(f'{q}: {size} from {u}')
    except Exception as e:
        print(f'{q}: Error {e}')
