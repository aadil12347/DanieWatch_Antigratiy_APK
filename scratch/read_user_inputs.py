import json

with open(r'C:\Users\mdani\.gemini\antigravity-ide\brain\515e5a60-19ca-4837-8107-6da474b49d02\.system_generated\logs\transcript.jsonl', 'r', encoding='utf-8', errors='ignore') as f:
    for line in f:
        try:
            obj = json.loads(line)
            if obj.get('type') == 'USER_INPUT':
                print(f"Step {obj.get('step_index')}: {obj.get('content')}\n---")
        except Exception:
            pass
