import undetected_chromedriver as uc
import time
import json
import sys

def sniff_streams():
    print("Launching Chrome...")
    options = uc.ChromeOptions()
    options.set_capability('goog:loggingPrefs', {'performance': 'ALL'})
    
    # Launch browser
    driver = uc.Chrome(options=options, version_main=148)
    
    print("Opening video page...")
    driver.get("https://player.videasy.net/movie/687163")
    
    print("\n" + "="*50)
    print("ACTION REQUIRED:")
    print("1. A Chrome window has opened.")
    print("2. If you see Cloudflare, let it pass.")
    print("3. CLICK THE 'PLAY' BUTTON in the video player.")
    print("4. Change servers/languages if you want to capture more links.")
    print("5. The stream links will automatically print below!")
    print("="*50 + "\n")
    
    seen_links = set()
    
    try:
        while True:
            # Continuously check performance logs for network requests
            logs = driver.get_log('performance')
            for entry in logs:
                try:
                    message = json.loads(entry['message'])['message']
                    if message['method'] == 'Network.responseReceived':
                        url = message['params']['response']['url']
                        
                        # Look for stream manifests or direct mp4 files
                        if '.m3u8' in url or '.mp4' in url:
                            if url not in seen_links:
                                seen_links.add(url)
                                print(f"[STREAM FOUND] {url}")
                                
                        # Look for API responses containing stream info
                        if 'sources-with-title' in url or 'sources?' in url:
                            if url not in seen_links:
                                seen_links.add(url)
                                print(f"[API CALLED] {url}")
                                
                except Exception:
                    pass
                    
            time.sleep(1) # Poll every second
            
    except KeyboardInterrupt:
        print("\nStopping sniffer...")
    finally:
        driver.quit()

if __name__ == "__main__":
    sniff_streams()
