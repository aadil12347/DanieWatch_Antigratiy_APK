import re
import sys
import json
import os

def analyze(filepath):
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # Find JS files
    url_pattern = r'https://player\.videasy\.net/[^\"\\]*\.js'
    matches = re.finditer(f'("url":\\s*"({url_pattern})").*?("response":\\s*{{.*?"content":\\s*{{.*?"text":\\s*"(.*?)".*?}})', content, re.DOTALL | re.IGNORECASE)
    
    js_files = []
    for match in matches:
        url = match.group(2)
        text = match.group(4)
        
        # Unescape text
        text = text.replace('\\n', '\n').replace('\\r', '').replace('\\"', '"').replace('\\\\', '\\')
        
        filename = url.split('/')[-1]
        js_files.append((filename, text))
        
    print(f"Found {len(js_files)} JS files.")
    
    for filename, text in js_files:
        print(f"--- {filename} ({len(text)} chars) ---")
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(text)
        print(f"Saved to {filename}")

if __name__ == '__main__':
    analyze(sys.argv[1])
