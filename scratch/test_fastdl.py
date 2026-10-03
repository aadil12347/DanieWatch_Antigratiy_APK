import urllib.request
import re

url = 'https://fastdl.zip/embed?download=vw5JVJJKLMzg5xOntzTYmxkgn'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Referer': 'https://fastdl.zip/'})
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        html = resp.read().decode('utf-8', errors='ignore')
    print('FastDL Status:', resp.status)
    print('Length:', len(html))
    g_match = re.search(r'link=(https://video-downloads\.googleusercontent\.com/[^\s"\'<>]+)', html)
    if g_match:
        print('GoogleUserContent direct stream:', g_match.group(1)[:120])
    re_match = re.search(r'var\s+reurl\s*=\s*[\'"]([^\'"]+)[\'"]', html)
    if re_match:
        print('reurl:', re_match.group(1)[:120])
except Exception as e:
    print('FastDL Error:', e)
