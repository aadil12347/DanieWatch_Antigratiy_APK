import urllib.request
import re
import sys
from urllib.parse import urlparse, parse_qs

def get_links(base_url):
    print(f"Fetching base URL: {base_url}")
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    }
    
    # 1. Fetch base page
    req = urllib.request.Request(base_url, headers=headers)
    try:
        with urllib.request.urlopen(req) as response:
            html = response.read().decode('utf-8', errors='ignore')
    except Exception as e:
        print(f"Error fetching base URL: {e}")
        return

    # 2. Extract title/filename from base page
    title_match = re.search(r'<title>(.*?)</title>', html, re.IGNORECASE)
    title = title_match.group(1) if title_match else "Unknown Title"
    print(f"Title: {title}")

    # 3. Find token URL
    token_url_match = re.search(r"var url\s*=\s*['\"](https://vcloud\.zip/[^'\"]+\?token=[^'\"]+)['\"]", html)
    if not token_url_match:
        token_url_match = re.search(r"var url\s*=\s*['\"](https?://[^'\"]+\?token=[^'\"]+)['\"]", html)
    
    if not token_url_match:
        print("Could not find token URL in the script tags!")
        return
    
    token_url = token_url_match.group(1)
    print(f"Found token URL: {token_url}")

    # 4. Fetch token page
    req2 = urllib.request.Request(token_url, headers={**headers, 'Referer': base_url})
    try:
        with urllib.request.urlopen(req2) as response2:
            html2 = response2.read().decode('utf-8', errors='ignore')
    except Exception as e:
        print(f"Error fetching token URL: {e}")
        return

    print("\n--- EXTRACTED DIRECT LINKS ---")
    hrefs = re.findall(r'href=["\']([^"\']+)["\']', html2)
    extracted = []
    
    for href in hrefs:
        # Ignore stylesheets, fonts, manifests
        if any(x in href for x in ['css', 'fonts', 'favicon', 'manifest', 'apple-touch-icon', 'admin', 'signup', 'telegram', 'google.com']):
            continue
        if href == '#' or not href.strip():
            continue
            
        # If it is a HubCloud / GPDL link, follow it to get the direct Google Drive link
        if 'hubcloud' in href or 'gpdl' in href:
            print(f"Found HubCloud Link: {href}")
            print("Resolving direct link from HubCloud...")
            try:
                req_hc = urllib.request.Request(href, headers=headers)
                with urllib.request.urlopen(req_hc) as res_hc:
                    final_hc_url = res_hc.geturl()
                    parsed_hc = urlparse(final_hc_url)
                    qp_hc = parse_qs(parsed_hc.query)
                    if 'link' in qp_hc:
                        direct_gdrive_url = qp_hc['link'][0]
                        print(f"  -> Resolved Direct Link (Google Drive): {direct_gdrive_url}")
                        extracted.append(direct_gdrive_url)
                    else:
                        print(f"  -> Failed to find 'link' parameter in redirected URL: {final_hc_url}")
            except Exception as e:
                print(f"  -> Error resolving HubCloud link: {e}")
        else:
            extracted.append(href)
            print(href)

    # Let's also print Android launch intents if they exist
    scripts = re.findall(r'<script.*?>([\s\S]*?)</script>', html2)
    for script in scripts:
        intent_match = re.search(r"host:\s*['\"](https?://[^'\"]+)['\"]", script)
        if intent_match:
            intent_url = intent_match.group(1)
            if intent_url not in extracted:
                extracted.append(intent_url)
                print(f"Android Intent Host URL: {intent_url}")

if __name__ == '__main__':
    target = 'https://vcloud.zip/1gxgqt66tuxd9kn'
    if len(sys.argv) > 1:
        target = sys.argv[1]
    get_links(target)
