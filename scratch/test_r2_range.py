import urllib.request, json

with open('scratch/s8_full_results.json') as f:
    data = json.load(f)

fslv2 = data['1']['vcloud_streams']['FSLv2']
fsl = data['1']['vcloud_streams']['FSL']

for name, url in [('FSLv2', fslv2), ('FSL', fsl)]:
    print(f'=== Testing Range request for {name} ===')
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Range': 'bytes=0-1023'})
    try:
        with urllib.request.urlopen(req) as r:
            cr = r.headers.get('Content-Range')
            cl = r.headers.get('Content-Length')
            print(f'  Status: {r.status}, Content-Range: {cr}, Content-Length: {cl}')
    except urllib.error.HTTPError as e:
        print(f'  HTTPError: {e.code} {e.reason}')
