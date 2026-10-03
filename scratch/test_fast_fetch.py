import urllib.request, re, time

url = 'https://vcloud.fit/zwo5kbpl7rt_t5l'
headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}

t0 = time.time()
req = urllib.request.Request(url, headers=headers)
resp = urllib.request.urlopen(req)

total_read = 0
found_token = False
found_size = False
content = b''

while True:
    chunk = resp.read(2048)
    if not chunk:
        break
    total_read += len(chunk)
    content += chunk
    text = content.decode('utf-8', errors='ignore')
    if not found_size and 'id="size"' in text:
        found_size = True
        print(f"Found size after reading only {total_read} bytes! ({time.time()-t0:.3f}s)")
    if not found_token and 'atob(atob(' in text:
        found_token = True
        print(f"Found token after reading only {total_read} bytes! ({time.time()-t0:.3f}s)")
    if found_size and found_token:
        print(f"==> ABORTING download early at {total_read} bytes in {time.time()-t0:.3f}s!")
        break

resp.close()
