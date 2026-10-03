import urllib.request, json

with open('scratch/s8_full_results.json') as f:
    data = json.load(f)

ep1 = data['1']
streams = ep1['vcloud_streams']

for name, url in streams.items():
    print(f'Testing {name}: {url[:80]}...')
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            cl = r.headers.get('Content-Length')
            ct = r.headers.get('Content-Type')
            print(f'  -> Status: {r.status}, Content-Length: {cl}, Content-Type: {ct}')
    except urllib.error.HTTPError as e:
        print(f'  -> HTTPError: {e.code} {e.reason}')
    except Exception as e:
        print(f'  -> Error: {e}')

# Test fastdl
furl = ep1['fastdl_stream']
print(f'\nTesting FastDL: {furl[:80]}...')
req = urllib.request.Request(furl, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        cl = r.headers.get('Content-Length')
        print(f'  -> Status: {r.status}, Content-Length: {cl}')
except urllib.error.HTTPError as e:
    print(f'  -> HTTPError: {e.code} {e.reason}')
