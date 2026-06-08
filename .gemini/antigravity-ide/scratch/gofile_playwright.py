import asyncio
from playwright.async_api import async_playwright
import sys
import json

async def extract_gofile(url):
    print(f"Launching Playwright to extract from: {url}")
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        )
        page = await context.new_page()
        
        links = []
        
        # Intercept network responses to catch the api.gofile.io/contents call
        async def handle_response(response):
            if "api.gofile.io/contents" in response.url:
                try:
                    text = await response.text()
                    data = json.loads(text)
                    print("Intercepted Gofile API Response!")
                    if data.get('status') == 'ok' and 'children' in data.get('data', {}):
                        children = data['data']['children']
                        for child_id, child_info in children.items():
                            if child_info.get('type') == 'file':
                                direct_link = child_info.get('link')
                                if direct_link:
                                    print(f"Discovered direct link: {direct_link}")
                                    links.append(direct_link)
                except Exception as e:
                    print(f"Error reading intercepted response: {e}")

        page.on("response", handle_response)
        
        try:
            # Open Gofile page
            await page.goto(url, timeout=30000)
            
            # Wait for content to load or API call to complete
            await page.wait_for_timeout(5000)
            
            # If no links discovered via API interception yet, let's look at anchor tags
            if not links:
                anchors = await page.query_selector_all("a[href*='gofile.io/download']")
                for anchor in anchors:
                    href = await anchor.get_attribute("href")
                    if href and href not in links:
                        links.append(href)
                        
            # If still nothing, print some debug text
            if not links:
                print("No direct links found in first 5 seconds. Page content summary:")
                content = await page.content()
                print(content[:1000])
                
        except Exception as e:
            print(f"Playwright error: {e}")
        finally:
            await browser.close()
            
        return links

if __name__ == '__main__':
    url = 'https://gofile.io/d/2uXnf4'
    if len(sys.argv) > 1:
        url = sys.argv[1]
    
    loop = asyncio.get_event_loop()
    res = loop.run_until_complete(extract_gofile(url))
    print("\n--- RESULTS ---")
    for link in res:
        print(link)
