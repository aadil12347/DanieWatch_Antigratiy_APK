const puppeteer = require('puppeteer');

(async () => {
    try {
        const browser = await puppeteer.launch({ 
            headless: 'new',
            args: ['--no-sandbox', '--disable-setuid-sandbox'] 
        });
        const page = await browser.newPage();
        
        await page.setRequestInterception(true);
        
        page.on('request', request => {
            const url = request.url();
            request.continue();
        });
        
        page.on('response', async response => {
            const url = response.url();
            // We want to capture APIs or m3u8 playlists
            if (url.includes('.m3u8') || url.includes('api') || url.includes('.mp4') || url.includes('source') || url.includes('delta')) {
                console.log('[RES]', url);
                try {
                    const type = response.request().resourceType();
                    if (type === 'xhr' || type === 'fetch') {
                        const text = await response.text();
                        console.log('[RES_BODY]', url, text.substring(0, 1000));
                    }
                } catch (e) {}
            }
        });

        console.log('Navigating to vidnest.fun...');
        await page.goto('https://vidnest.fun/movie/412862?server=delta', { waitUntil: 'networkidle2', timeout: 30000 });
        
        // Wait a bit more for any async requests
        await new Promise(r => setTimeout(r, 5000));
        
        await browser.close();
        console.log('Done.');
    } catch (e) {
        console.error(e);
    }
})();
