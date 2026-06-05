import json
with open('extracted_logs.txt', 'r', encoding='utf-16') as f:
    for line in f:
        if 'DEBUG CLICK' in line:
            try:
                json_str = line.split('[DEBUG CLICK] ')[1].strip()
                data = json.loads(json_str)
                print(f"CLICK: tagName={data.get('tagName')} text='{data.get('text')}' class={data.get('className')}")
            except Exception as e:
                pass
