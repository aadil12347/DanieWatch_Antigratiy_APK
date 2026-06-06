import json
import base64
import urllib.request
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

def base64url_decode(payload):
    # Fix padding
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
    # cryptography library expects ciphertext + tag
    decrypted = aesgcm.decrypt(iv, ciphertext + tag, None)
    return json.loads(decrypted.decode('utf-8'))

key = "a8f2a1b5e9c470814f6b2c3a5d8e7f9c1a2b3c4d5e3f7a8b8cad1e2d0a4d5c5b"
url = "https://uwu.eat-peach.sbs/moviebox/movie/687163"

req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req) as response:
        resp_data = json.loads(response.read().decode('utf-8'))
        if resp_data.get("isEncrypted"):
            decrypted = decrypt_payload(resp_data["data"], key)
            print("Decrypted successfully:")
            print(json.dumps(decrypted, indent=2))
        else:
            print("Not encrypted:")
            print(json.dumps(resp_data, indent=2))
except Exception as e:
    print(f"Error: {e}")

