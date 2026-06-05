const puppeteer = require('puppeteer');
const fs = require('fs');

(async () => {
    console.log("Launching browser...");
    
    const browser = await puppeteer.launch({ 
        headless: false, 
        defaultViewport: null,
        channel: 'chrome', // Use your system's Google Chrome directly
        args: ['--start-maximized']
    });
    
    const page = await browser.newPage();
    
    // --- ANTI-DETECTION MAGIC ---
    await page.evaluateOnNewDocument(() => {
        // 1. Hide that we are using an automated browser
        Object.defineProperty(navigator, 'webdriver', { get: () => false });
        
        // 2. Fake the Chrome runtime object
        window.chrome = { runtime: {} };
        
        // 3. Block the website from using JavaScript to close the window!
        window.close = function() { 
            console.log("Blocked site from closing the window"); 
        };
    });

    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');

    const networkLogs = [];

    // Capture all outgoing requests
    page.on('request', request => {
        networkLogs.push({
            type: 'Request',
            method: request.method(),
            url: request.url(),
            resourceType: request.resourceType(),
            postData: request.postData() || null
        });
        
        // Save dynamically so if the script stops, you still have the data
        fs.writeFileSync('network_logs_live.json', JSON.stringify(networkLogs, null, 2));
    });

    console.log("Navigating to https://cinemaos.tech/movie/watch/454639...");
    
    try {
        await page.goto('https://cinemaos.tech/movie/watch/454639', { 
            waitUntil: 'domcontentloaded', 
            timeout: 60000 
        });
    } catch(err) {
        console.log("Navigation took a while, continuing anyway...");
    }

    console.log("\n==========================================================");
    console.log("✅ Browser is open!");
    console.log("🖱️  Click around as much as you want to trigger the videos.");
    console.log("💾 All requests are saving to 'network_logs_live.json' in real-time.");
    console.log("❌ When you are completely done, JUST CLOSE THE CHROME WINDOW.");
    console.log("==========================================================\n");

    // Wait until the user manually closes the browser
    await new Promise(resolve => {
        browser.on('disconnected', resolve);
    });

    console.log("Browser was closed. Creating final sorted log files...");

    // Filter logs if you want to find specific things (like .m3u8 or .mp4)
    const mediaRequests = networkLogs.filter(req => 
        req.url.includes('.m3u8') || 
        req.url.includes('.mp4') ||
        req.url.includes('api') ||
        req.resourceType === 'media' ||
        req.resourceType === 'fetch' ||
        req.resourceType === 'xhr'
    );

    fs.writeFileSync('network_logs.json', JSON.stringify(networkLogs, null, 2));
    fs.writeFileSync('media_logs.json', JSON.stringify(mediaRequests, null, 2));

    // Cleanup the temporary live file
    if (fs.existsSync('network_logs_live.json')) {
        fs.unlinkSync('network_logs_live.json');
    }

    console.log(`\nCaptured a total of ${networkLogs.length} requests.`);
    console.log(`Wrote complete logs to network_logs.json`);
    console.log(`Wrote filtered API/Media logs to media_logs.json for easier reading.`);
    console.log("Done! Exiting.");
    process.exit(0);
})();
