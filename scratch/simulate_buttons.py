import re, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

with open('scratch/got_page.html', 'r', encoding='utf-8') as f:
    html = f.read()

# Simulate extractPostButtons logic
from html.parser import HTMLParser

class SimpleHTMLParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.elements = []  # (tag, text, attrs, pos)
        self.current_tag = None
        self.current_text = ''
        self.current_attrs = {}
        self.in_tag = False
        
    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            self.current_tag = 'a'
            self.current_attrs = dict(attrs)
            self.current_text = ''
            self.in_tag = True
        elif tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'strong']:
            self.current_tag = tag
            self.current_attrs = dict(attrs)
            self.current_text = ''
            self.in_tag = True
    
    def handle_data(self, data):
        if self.in_tag:
            self.current_text += data
    
    def handle_endtag(self, tag):
        if self.in_tag and tag == self.current_tag:
            self.elements.append((self.current_tag, self.current_text.strip(), self.current_attrs, self.getpos()))
            self.in_tag = False

parser = SimpleHTMLParser()
parser.feed(html)

# Now simulate the button extraction
# First, list all anchors with nexdrive/vcloud/etc
nexdrive_domains = ['nexdrive', 'vgmlink', 'gdflix', 'fastdl', 'filebee', 'hubcloud', 'vcloud', 'pixeldrain']

buttons = []
headings = []

for tag, text, attrs, pos in parser.elements:
    if tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'strong']:
        headings.append((tag, text, pos))
    elif tag == 'a':
        href = attrs.get('href', '')
        lh = href.lower()
        if any(d in lh for d in nexdrive_domains):
            # Find nearest quality heading above this
            quality = '720p'  # default
            season = 1  # default
            
            for htag, htext, hpos in reversed(headings):
                ht_lower = htext.lower()
                
                # Quality
                if '2160p' in ht_lower or '4k' in ht_lower:
                    quality = '2160p'
                    break
                elif '1080p' in ht_lower:
                    quality = '1080p'
                    break
                elif '720p' in ht_lower:
                    quality = '720p'
                    break
                elif '480p' in ht_lower:
                    quality = '480p'
                    break
            
            # Season
            for htag, htext, hpos in reversed(headings):
                sm = re.search(r'(?:Season|S)\s*0*(\d+)', htext, re.I)
                if sm:
                    sn = int(sm.group(1))
                    if 0 < sn < 100:
                        season = sn
                        break
            
            lt = text.lower()
            is_batch = 'batch' in lt or 'zip' in lt or 'pack' in lt
            
            buttons.append({
                'text': text[:60],
                'href': href,
                'quality': quality,
                'season': season,
                'is_batch': is_batch,
            })

print(f"Total buttons found: {len(buttons)}")
print()
for b in buttons:
    print(f"  S{b['season']} {b['quality']:6s} batch={str(b['is_batch']):5s} [{b['text'][:50]:50s}] -> {b['href']}")
