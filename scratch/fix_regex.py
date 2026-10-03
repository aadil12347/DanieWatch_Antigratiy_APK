filepath = r"e:\0.1 Github Repo\DanieWatch Apk VidEasy\lib\services\vcloud_extractor.dart"

with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Find the exact substring byte-by-byte
target = "atob2UrlRegExp = RegExp(r"
idx = content.find(target)
if idx < 0:
    print("ERROR: target not found")
else:
    # Find the full line
    line_start = content.rfind('\n', 0, idx) + 1
    line_end = content.find('\n', idx)
    old_line = content[line_start:line_end]
    print(f"Found at index {idx}")
    print(f"Old line: {old_line}")
    
    # Build the new line with proper regex
    new_line = '        final atob2UrlRegExp = RegExp(r"""atob\\s*\\(\\s*atob\\s*\\(\\s*[\'"]([A-Za-z0-9+/=]{10,})[\'"]\\s*\\)\\s*\\)""", caseSensitive: false);'
    print(f"New line: {new_line}")
    
    content = content[:line_start] + new_line + content[line_end:]
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print("SUCCESS!")
