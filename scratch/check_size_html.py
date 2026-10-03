import urllib.request, re

url = 'https://vcloud.fit/zwo5kbpl7rt_t5l'
headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
html = urllib.request.urlopen(urllib.request.Request(url, headers=headers)).read().decode('utf-8')

idx = html.find('id="size"')
if idx != -1:
    print('RAW SNIPPET:', repr(html[idx:idx+80]))

m = re.search(r'id=["\']size["\'][^>]*>(.*?)<', html, re.I | re.S)
if m:
    print('MATCH:', repr(m.group(1)))
else:
    print('NO MATCH')
