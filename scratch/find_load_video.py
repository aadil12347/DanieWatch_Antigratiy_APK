with open("assets/html/player.html", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx, line in enumerate(lines):
    if "loadVideo" in line:
        print(f"Line {idx+1}: {line.strip()}")
        # print 20 lines after
        for j in range(1, 40):
            if idx + j < len(lines):
                print(f"  +{j}: {lines[idx+j].strip()}")
        break
