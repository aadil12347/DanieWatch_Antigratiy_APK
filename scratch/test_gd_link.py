import requests

url = "https://gpdl2.hubcloud.cx/?id=300b44600b91bb7e352ea98e59629dc09d6c32ed4962207957e5e09d6c7950a63b222ce34057241ca97857052bd7b6316b57cec7daf05be760a49e14ef0f2cc572b993145d649553f5975c3ba642e7427234f8b6345088b3152a83b313b03ca97511e2be2e347ce4800318adb71d9961::424527fdfb3c7a71e61ca84d61e62ff2"
headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
}

print("Fetching first hop...")
session = requests.Session()
r = session.get(url, headers=headers, allow_redirects=False)
print("Status:", r.status_code)
print("Headers:", r.headers)
if 'Location' in r.headers:
    redirect_url = r.headers['Location']
    print("Redirect to:", redirect_url)
    
    print("\nFetching second hop...")
    r2 = session.get(redirect_url, headers=headers, allow_redirects=False)
    print("Status:", r2.status_code)
    print("Headers:", r2.headers)
    
    if 'Location' in r2.headers:
        redirect_url2 = r2.headers['Location']
        print("Redirect to:", redirect_url2)
        
        print("\nFetching third hop...")
        r3 = session.get(redirect_url2, headers=headers, allow_redirects=False)
        print("Status:", r3.status_code)
        print("Headers:", r3.headers)
        if 'Location' in r3.headers:
            print("Redirect to:", r3.headers['Location'])
        else:
            print("Response body first 500 chars:", r3.text[:500])
    else:
        print("Response body first 1000 chars:", r2.text[:1000])
else:
    print("Response body:", r.text[:1000])
