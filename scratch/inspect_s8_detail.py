import re, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

with open('scratch/got_page.html', 'r', encoding='utf-8') as f:
    html = f.read()

heading_re = re.compile(r'<(h[1-6]|strong)[^>]*>(.*?)</\1>', re.I | re.S)
headings = list(heading_re.finditer(html))

print(f"Total headings: {len(headings)}")

# Find Season 8 headings and their following links
print("\n=== SEASON 8 HEADINGS AND LINKS ===")
for i, m in enumerate(headings):
    raw_text = re.sub(r'<[^>]+>', '', m.group(2)).strip()
    lower = raw_text.lower()
    # Look for Season 8 specific section headings (not "Season 1 - 8" title)
    if 'season 8' in lower or 's08' in lower:
        start = m.end()
        end_pos = headings[i+1].start() if i+1 < len(headings) else len(html)
        section = html[start:end_pos]
        links = re.findall(r'href=["\']([^"\']+)["\']', section, re.I)
        nexdrive_links = [l for l in links if 'nexdrive' in l.lower() or 'vcloud' in l.lower() or 'hubcloud' in l.lower()]
        
        print(f"\nHeading #{i}: <{m.group(1)}> text: {raw_text[:150]}")
        print(f"  NexDrive/VCloud links: {len(nexdrive_links)}")
        for l in nexdrive_links[:10]:
            print(f"    -> {l}")

# Let's also look at ALL headings near the nexdrive links for Season 8 (by position in page)
print("\n\n=== ALL HEADINGS (with position) ===")
for i, m in enumerate(headings):
    raw_text = re.sub(r'<[^>]+>', '', m.group(2)).strip()
    # Show quality/season headings only
    lower = raw_text.lower()
    if any(kw in lower for kw in ['season', '480', '720', '1080', 'batch', 'zip', 'download']):
        print(f"  #{i} pos={m.start()} <{m.group(1)}>: {raw_text[:150]}")

# Now simulate what extractPostButtons does - look at anchors with nexdrive/vcloud/hubcloud
print("\n\n=== EXTRACTPOSTBUTTONS SIMULATION ===")
anchor_re = re.compile(r'<a\s+[^>]*href=["\']([^"\']*(?:nexdrive|vcloud|hubcloud|gdflix|fastdl|filebee)[^"\']*)["\'][^>]*>(.*?)</a>', re.I | re.S)
for m in anchor_re.finditer(html):
    href = m.group(1)
    text = re.sub(r'<[^>]+>', '', m.group(2)).strip()
    pos = m.start()
    
    # Find nearest quality heading before this
    quality = "unknown"
    season = 0
    for h in headings:
        if h.start() > pos:
            break
        ht = re.sub(r'<[^>]+>', '', h.group(2)).strip().lower()
        if '480' in ht: quality = '480p'
        elif '720' in ht: quality = '720p'
        elif '1080' in ht: quality = '1080p'
        
        sm = re.search(r'season\s*(\d+)', ht, re.I)
        if sm:
            sn = int(sm.group(1))
            if 0 < sn < 100:
                season = sn
    
    print(f"  [{text[:50]:50s}] S{season} {quality:6s} -> {href}")
