import urllib.request
import json
import time

def test_gofile():
    print("Waiting 10 seconds to clear rate limit...")
    time.sleep(10)
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Origin': 'https://gofile.io',
        'Referer': 'https://gofile.io/',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
    }

    # 1. Get Guest Token
    print("Creating guest account...")
    req_acc = urllib.request.Request(
        'https://api.gofile.io/accounts',
        method='POST',
        headers={**headers, 'Content-Type': 'application/json'},
        data=b'{}'
    )
    
    try:
        with urllib.request.urlopen(req_acc) as res_acc:
            acc_data = json.loads(res_acc.read().decode('utf-8'))
            token = acc_data['data']['token']
            print(f"Guest Token: {token}")
    except Exception as e:
        print(f"Failed to create guest account: {e}")
        return

    # 2. Get Folder Contents
    print("Fetching folder contents...")
    req_content = urllib.request.Request(
        'https://api.gofile.io/contents/2uXnf4',
        headers={
            **headers,
            'Authorization': f'Bearer {token}',
            'X-Website-Token': '4fd6sg89d7s6',
        }
    )
    
    try:
        with urllib.request.urlopen(req_content) as res_content:
            content_data = json.loads(res_content.read().decode('utf-8'))
            print("Successfully retrieved content data!")
            print(json.dumps(content_data, indent=2)[:2000])
    except Exception as e:
        print(f"Failed to retrieve content: {e}")
        if hasattr(e, 'read'):
            print("Error details:", e.read().decode('utf-8'))

if __name__ == '__main__':
    test_gofile()
