const fs = require('fs');
const https = require('https');

const customAlphabet = "RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/=";
const standardAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

function decodeCustomBase64(input) {
    let standardBase64 = "";
    for (let i = 0; i < input.length; i++) {
        const char = input[i];
        const index = customAlphabet.indexOf(char);
        if (index !== -1) {
            standardBase64 += standardAlphabet[index];
        } else {
            standardBase64 += char;
        }
    }
    return Buffer.from(standardBase64, 'base64').toString('utf-8');
}

const url = "https://new.vidnest.fun/allmovies/movie/1327819";

https.get(url, (res) => {
    let rawData = '';
    res.on('data', (chunk) => { rawData += chunk; });
    res.on('end', () => {
        try {
            const parsedData = JSON.parse(rawData);
            if (parsedData.encrypted && parsedData.data) {
                const decoded = decodeCustomBase64(parsedData.data);
                console.log(decoded);
            } else {
                console.log("Not encrypted or missing data field");
                console.log(rawData);
            }
        } catch (e) {
            console.error(e.message);
        }
    });
}).on('error', (e) => {
    console.error(`Got error: ${e.message}`);
});
