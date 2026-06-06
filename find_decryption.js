const fs = require('fs');

(async () => {
    const urls = [
        "https://vidnest.fun/_next/static/chunks/a3f6c22d97a69088.js",
        "https://vidnest.fun/_next/static/chunks/00cb8966bcf22375.js",
        "https://vidnest.fun/_next/static/chunks/d4cf4caae891f664.js",
        "https://vidnest.fun/_next/static/chunks/69be39811437728d.js",
        "https://vidnest.fun/_next/static/chunks/turbopack-b527ebc3afe4110c.js",
        "https://vidnest.fun/_next/static/chunks/744355e03808d4c7.js",
        "https://vidnest.fun/_next/static/chunks/ff1a16fafef87110.js",
        "https://vidnest.fun/_next/static/chunks/b5dc6c688de67194.js",
        "https://vidnest.fun/_next/static/chunks/4fa3ead9609cf2d6.js",
        "https://vidnest.fun/_next/static/chunks/66b231c2403f619d.js",
        "https://vidnest.fun/_next/static/chunks/6c30b25e2bb0f61b.js",
        "https://vidnest.fun/_next/static/chunks/31dd2cd50f2a288b.js",
        "https://vidnest.fun/_next/static/chunks/fd1f705872333be6.js"
    ];

    for (const url of urls) {
        try {
            const res = await fetch(url);
            const text = await res.text();
            if (text.includes('decryptCipherResponse') || text.includes('AES') || text.includes('decrypt')) {
                console.log(`\n--- Found in ${url} ---`);
                
                // Print a snippet around the match
                const matchIndex = text.indexOf('decryptCipherResponse');
                if (matchIndex !== -1) {
                    console.log('Match decryptCipherResponse:', text.substring(Math.max(0, matchIndex - 100), matchIndex + 400));
                }
                
                const cryptoIndex = text.indexOf('crypto.subtle');
                if (cryptoIndex !== -1) {
                    console.log('Match crypto:', text.substring(Math.max(0, cryptoIndex - 100), cryptoIndex + 1500));
                }

                // If it looks like AES or crypto-js
                const aesIndex = text.indexOf('AES.decrypt');
                if (aesIndex !== -1) {
                    console.log('Match AES.decrypt:', text.substring(Math.max(0, aesIndex - 100), aesIndex + 500));
                }
            }
        } catch (e) {
            console.error(`Failed ${url}:`, e.message);
        }
    }
})();
