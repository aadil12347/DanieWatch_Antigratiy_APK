from bs4 import BeautifulSoup
import re

with open('scratch/got_page.html', 'r', encoding='utf-8') as f:
    html = f.read()

soup = BeautifulSoup(html, 'html.parser')
for a in soup.find_all('a', href=True):
    h = a['href']
    t = a.get_text()
    if 'nexdrive' in h:
        print(f'{repr(t.strip()[:60])} -> {h}')
