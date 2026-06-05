import asyncio
from playwright.async_api import async_playwright
import json

async def run(playwright):
    # Launch Chromium in a visible window
    browser = await playwright.chromium.launch(headless=False)
    context = await browser.new_context(
        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"
    )
    page = await context.new_page()

    print("\n" + "="*60)
    print("📺 VIDEASY NETWORK ANALYZER STARTED")
    print("="*60)
    print("Listening for all network requests to api.videasy.net...")
    print("The browser window is now open.")
    print("👉 Please click the settings, change languages/resolutions, etc.")
    print("All hidden API calls and JSON payloads will be logged right here.")
    print("Press Ctrl+C to stop the script when you're done.")
    print("="*60 + "\n")

    # Intercept and print console messages
    page.on("console", lambda msg: print(f"[Browser Console]: {msg.text}"))

    # Intercept and print network responses
    async def handle_response(response):
        try:
            url = response.url
            # Filter for videasy API requests, or media files
            if "videasy.net" in url and ("api" in url or "source" in url or "server" in url or ".m3u8" in url or ".mp4" in url):
                print(f"\n[NETWORK LOG] -> {url}")
                print(f"  Status: {response.status}")
                content_type = response.headers.get('content-type', '')
                
                if 'application/json' in content_type:
                    body = await response.json()
                    print(f"  Payload (JSON): {json.dumps(body, indent=2)}")
                else:
                    body = await response.text()
                    print(f"  Content-Type: {content_type}")
                    print(f"  Payload (Text): {body[:1000]}")
        except Exception as e:
            pass # Ignore read errors for media streams that are still streaming

    page.on("response", handle_response)

    # Open the player page
    print("Loading player...")
    await page.goto("https://player.videasy.net/movie/687163")
    
    # Keep the script running forever so you can interact
    while True:
        await asyncio.sleep(1)

async def main():
    async with async_playwright() as playwright:
        await run(playwright)

if __name__ == "__main__":
    asyncio.run(main())
