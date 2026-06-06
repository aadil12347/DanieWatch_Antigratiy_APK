const fs = require('fs');

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

const data = "lOybxZyG35gbEsXFlOymI5HnIuybEsXoEGyGIaJOIuET7TymxZijDbmzLQxGF5gNvfpQFQrULavzF6yWL0yU354qx5HqI6EhEnNXFaiXETjTxZGjI6EhEaNUDOEUEqJOF0EhEaNCxZBb7TezK6gNDavmLM2jk04dIuGrKM2wvQJ9l04sFQCzDPiOI5HrkTWXL5HO3Q1rvfRjLQJN7fGTksDwv8ys3sEP3aJnIfGsIMRbvsD47f3wkb24LCgVJpgbDfH6DQNZJZGqFng7AGJ6kn9OMJvUFGx35nJnMA4p5qXiJQAgMAiKlngrIHXVJpewAsy6JgIE5niUKaJdK8rMDQjwJqxIFGxClfysK5N5JfEwKQH0AaXuiJEO3AW6JGxhKCI5DnyAJpJ5ingcAsHIxbRjJnewFJiHFfHvMaiJJfkgiJIdlHxAvnI5Afmwvb1jvs14kMkQ7s3CLspw709wvMAtkMRg7syN7M1gIs2jvfvNk8yTkaJG3snjI8pPksIT753g3MEQk5HnkbnPkM1Pv83gv5HG3Qp43MA4vbvsvMJa3M1Qk8phcMid3Jy55HiJJnJ7MuBuAq1CkHAjIgNAiJI5A0WXFaiGl04rkPA9EqgxL0yCFPiNFpwNFaxg35xGDOEhkuCV";

console.log(decodeCustomBase64(data));
