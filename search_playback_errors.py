with open(r'C:\Users\mdani\.gemini\antigravity-ide\brain\072adc5c-f263-4b68-8402-95c6612e1f0e\.system_generated\tasks\task-754.log', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Search for relevant playback logs or exceptions in the last 200 lines
print("--- Last 150 Log Lines ---")
for line in lines[-150:]:
    cleaned = line.encode('ascii', errors='replace').decode('ascii').strip()
    if any(kw in cleaned for kw in ['Exception', 'Error', 'failed', 'Extraction', 'Vcloud', 'VCloud', 'BetterPlayer', 'ExoPlayer', 'PlaybackState', 'stream']):
        print(cleaned)
