import urllib.request
from bs4 import BeautifulSoup

url = 'https://vegamovies.gallery/category/featured/'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
html = urllib.request.urlopen(req, timeout=10).read().decode('utf-8')
soup = BeautifulSoup(html, 'html.parser')

post_links = []
for a in soup.find_all('a'):
    href = a.get('href', '')
    if '/download-' in href and 'season' not in href.lower() and href not in post_links:
        post_links.append(href)

print(f"Found {len(post_links)} movie posts")
for p in post_links[:5]:
    try:
        p_html = urllib.request.urlopen(urllib.request.Request(p, headers={'User-Agent': 'Mozilla/5.0'}), timeout=10).read().decode('utf-8')
        p_soup = BeautifulSoup(p_html, 'html.parser')
        btns = []
        for a in p_soup.find_all('a'):
            t = a.get_text().strip()
            h = a.get('href', '')
            if any(k in h for k in ['nexdrive', 'vcloud', 'fastdl']):
                btns.append((t, h))
        if btns:
            print(f"\nPost: {p}")
            for t, h in btns[:4]:
                print(f"  btn: {t[:40]} -> {h}")
    except Exception as e:
        print(f"Error {p}: {e}")
