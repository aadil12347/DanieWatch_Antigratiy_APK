import json
import base64
import urllib.request
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from collections import defaultdict

def base64url_decode(payload):
    payload = payload.replace('-', '+').replace('_', '/')
    padding = len(payload) % 4
    if padding:
        payload += '=' * (4 - padding)
    return base64.b64decode(payload)

def decrypt_payload(data, key_hex):
    iv_b64, cipher_b64, tag_b64 = data.split('.')
    iv = base64url_decode(iv_b64)
    ciphertext = base64url_decode(cipher_b64)
    tag = base64url_decode(tag_b64)
    key = bytes.fromhex(key_hex)
    aesgcm = AESGCM(key)
    decrypted = aesgcm.decrypt(iv, ciphertext + tag, None)
    return json.loads(decrypted.decode('utf-8'))

key = 'a8f2a1b5e9c470814f6b2c3a5d8e7f9c1a2b3c4d5e3f7a8b8cad1e2d0a4d5c5b'

endpoints = [
    ('Iron', 'https://uwu.eat-peach.sbs/moviebox/movie/1304313'),
    ('Spider', 'https://usa.eat-peach.sbs/holly/movie/1304313'),
    ('Wolf', 'https://usa.eat-peach.sbs/air/movie/1304313'),
    ('Multi', 'https://usa.eat-peach.sbs/multi/movie/1304313'),
    ('Dark', 'https://uwu.eat-peach.sbs/net/movie/1304313')
]

all_sources = []

for name, url in endpoints:
    req = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Referer': 'https://peachify.top/',
        'Origin': 'https://peachify.top'
    })
    try:
        with urllib.request.urlopen(req) as response:
            resp_data = json.loads(response.read().decode('utf-8'))
            sources = []
            if resp_data.get('isEncrypted'):
                decrypted = decrypt_payload(resp_data['data'], key)
                sources = decrypted.get('sources', [])
            else:
                sources = resp_data.get('sources', [])
                
            for s in sources:
                s['providerName'] = name
                all_sources.append(s)
    except Exception as e:
        pass

grouped = defaultdict(list)
for s in all_sources:
    dub = s.get('dub', 'Unknown')
    grouped[dub].append(s)

for dub, srcs in grouped.items():
    print(f'--- DUB: {dub} ---')
    for s in srcs:
        print(f"Provider: {s['providerName']} | Type: {s['type']} | URL: {s['url']}")
