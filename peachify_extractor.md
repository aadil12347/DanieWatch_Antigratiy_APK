# Peachify Extractor Documentation

This document explains how to extract direct stream URLs and subtitles from the Peachify streaming provider (`peachify.top`).

## 1. API Endpoints

Peachify aggregates sources from multiple internal "providers" (servers). Each provider has a base API endpoint.

### Available Providers
- **Iron** (`moviebox`): `https://uwu.eat-peach.sbs/moviebox`
- **Spider** (`holly`): `https://usa.eat-peach.sbs/holly`
- **Wolf** (`air`): `https://usa.eat-peach.sbs/air`
- **Multi** (`multi`): `https://usa.eat-peach.sbs/multi`
- **Dark** (`net`): `https://uwu.eat-peach.sbs/net`

### Request Format
To get the stream data, make a `GET` request to one of the providers.

**Movies:**
```
{api_base}/movie/{tmdb_id}
```
*Example:* `https://uwu.eat-peach.sbs/moviebox/movie/687163`

**TV Shows:**
```
{api_base}/tv/{tmdb_id}/{season}/{episode}
```
*Example:* `https://uwu.eat-peach.sbs/moviebox/tv/76479/1/1`

### Required Headers
The API requires the following headers to prevent `403 Forbidden` errors:
- `Origin`: `https://peachify.top`
- `Referer`: `https://peachify.top/`

---

## 2. Decrypting the Response

The API responds with JSON. You must check the `isEncrypted` boolean field.

### If `isEncrypted` is `false`
The `sources` and `subtitles` are directly available in the JSON response.

### If `isEncrypted` is `true`
The response contains a `data` field which is an AES-GCM encrypted string.

**Decryption Details:**
1. **Key:** `a8f2a1b5e9c470814f6b2c3a5d8e7f9c1a2b3c4d5e3f7a8b8cad1e2d0a4d5c5b` (Hex encoded).
2. **Payload format:** The `data` string is formatted as `IV.CIPHERTEXT.AUTHTAG`, encoded in Base64URL.
3. **Process:**
   - Split the `data` string by the `.` character into `iv_b64`, `cipher_b64`, and `tag_b64`.
   - Decode each part using Base64URL decoding (remember to add `=` padding if necessary).
   - Use AES-GCM decryption with the decoded `IV`, `CIPHERTEXT`, and `AUTHTAG` to recover the plaintext JSON string.
   - Parse the decrypted JSON string.

### Python Decryption Example
```python
import json
import base64
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

def base64url_decode(payload):
    payload = payload.replace('-', '+').replace('_', '/')
    padding = len(payload) % 4
    if padding:
        payload += '=' * (4 - padding)
    return base64.b64decode(payload)

def decrypt_payload(data_str):
    key_hex = 'a8f2a1b5e9c470814f6b2c3a5d8e7f9c1a2b3c4d5e3f7a8b8cad1e2d0a4d5c5b'
    iv_b64, cipher_b64, tag_b64 = data_str.split('.')
    
    iv = base64url_decode(iv_b64)
    ciphertext = base64url_decode(cipher_b64)
    tag = base64url_decode(tag_b64)
    key = bytes.fromhex(key_hex)
    
    aesgcm = AESGCM(key)
    # The cryptography library expects ciphertext + tag concatenated
    decrypted = aesgcm.decrypt(iv, ciphertext + tag, None)
    return json.loads(decrypted.decode('utf-8'))
```

---

## 3. Extracting the Direct Stream URL

The decrypted JSON will have a `sources` array. Each object in `sources` has a `url` property.

Sometimes, the `url` is a direct `m3u8` or `mp4` link. However, often it is wrapped in a Peachify proxy URL, for example:
`https://up-1.eat-peach.sbs/m3u8-proxy?url=https%3A%2F%2F...&headers=%7B...%7D`

To get the actual direct stream link:
1. Parse the proxy URL's query parameters.
2. Extract the `url` parameter. This is the direct, playable stream URL.
3. Extract the `headers` parameter. Parse it as JSON. These are the HTTP headers (e.g., `Referer`, `Origin`, `User-Agent`) that the video player *must* send when requesting the stream URL.

### Example Proxy Extraction
```python
from urllib.parse import urlparse, parse_qs
import json

proxy_url = "https://up-1.eat-peach.sbs/m3u8-proxy?url=https%3A%2F%2Fgoodstream.cc%2Fpl%2FD1134V...&headers=%7B%22referer%22%3A%22https%3A%2F%2Fgoodstream.cc%2F%22%7D"

parsed = urlparse(proxy_url)
query_params = parse_qs(parsed.query)

direct_stream_url = query_params.get("url", [None])[0]
required_headers_json = query_params.get("headers", ["{}"])[0]
required_headers = json.loads(required_headers_json)

print("Direct Stream:", direct_stream_url)
print("Required Headers:", required_headers)
```

The resulting `direct_stream_url` and `required_headers` can then be passed to ExoPlayer or any video player to play the stream directly.
