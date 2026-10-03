import os

path = r"C:\Users\mdani\AppData\Local\Pub\Cache\hosted\pub.dev\echo_wifi_lock-0.0.1\android\src\main\kotlin\com\echo\echo_wifi_lock\EchoWifiLockPlugin.kt"
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    
    old_text = 'TODO("Not yet implemented")'
    new_text = '// handled'
    if old_text in text:
        text = text.replace(old_text, new_text)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print("Successfully replaced all TODO('Not yet implemented') in EchoWifiLockPlugin.kt")
    else:
        print("TODO not found or already patched")
else:
    print("Path does not exist")
