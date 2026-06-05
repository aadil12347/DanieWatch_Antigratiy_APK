from playwright.sync_api import sync_playwright

def get_docs():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto("https://www.videasy.net/docs", wait_until="networkidle")
        
        # Give React time to render
        page.wait_for_timeout(3000)
        
        text = page.evaluate("document.body.innerText")
        with open("docs.txt", "w", encoding="utf-8") as f:
            f.write(text)
        
        browser.close()

if __name__ == "__main__":
    get_docs()
