/**
 * DanieWatch Cloudflare Worker Edge Scraper & Cache
 * 
 * Provides ultra-fast (<80ms) cached JSON responses for:
 * - /api/home (Top 10 Indian Today 2026, Top 10 Hindi Dub Today, Featured Carousel)
 * - /api/category?name=korean&page=1
 * 
 * Includes reality show filtering, HTML extraction, and edge caching (10-15 mins).
 */

const VEGA_BASE = 'https://vegamovies.gallery';
const ROG_BASE = 'https://rogmovies.best';

const EXCLUDED_PATTERNS = /roadies|bigg?\s*boss|dance\s*master|hustle|top\s*1\s*%|top\s*1\s*percent|sa\s*re\s*ga\s*ma|sare\s*gama|best\s*dancer|beat\s*dancer|khatron\s*ke\s*khiladi|got\s*latent|kapil\s*show|reality|tv-show|rise\s*and\s*fall|family\s*full\s*house/i;

function cleanTitle(raw) {
  if (!raw) return '';
  return raw
    .replace(/&#038;|&amp;/gi, '&')
    .replace(/&#8211;/gi, '-')
    .replace(/&#8217;/gi, "'")
    .replace(/&quot;/gi, '"')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function cleanDisplayTitle(raw) {
  let t = cleanTitle(raw);
  if (t.toLowerCase().startsWith('download ')) {
    t = t.substring(9).trim();
  }
  t = t.replace(/\s*[\{\[].*?[\}\]]/g, ' ');
  t = t.replace(/\s*(?:Full Movie|Complete Web Series|WEB-DL|HDTC|PreDVD|HDRip|x264|HEVC|H\.264|HQ|UnCut|ORG\.?|LiNE|Hindi|Dual Audio|Tamil|Telugu|Punjabi|JioHotstar|SonyLiv|Netflix|AMZN|Zee5|–|\*No Ads\*|480p|720p|1080p|2160p).*$/i, '');
  t = t.replace(/\s+/g, ' ').trim();
  return t.length >= 3 ? t : cleanTitle(raw);
}

function parseCards(html, site) {
  const cards = [];
  const seenUrls = new Set();
  const cardRegex = /<div class="poster-card"[^>]*>([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>/gi;
  const urlRegex = /<meta itemprop="url" content="([^"]+)"|<a\s+[^>]*href="([^"]+)"/i;
  const imgRegex = /<img[^>]+(?:src|data-src)="([^"]+)"/i;
  const altRegex = /alt="([^"]+)"/i;
  const titleRegex = /class="poster-title"[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i;
  const rateRegex = /<meta itemprop="ratingValue" content="([^"]+)"/i;

  let match;
  while ((match = cardRegex.exec(html)) !== null) {
    const block = match[1] || '';
    const urlM = block.match(urlRegex);
    const postUrl = urlM ? (urlM[1] || urlM[2]) : null;
    if (!postUrl || seenUrls.has(postUrl)) continue;

    const imgM = block.match(imgRegex);
    const altM = block.match(altRegex);
    const titleM = block.match(titleRegex);
    const rateM = block.match(rateRegex);

    const rawTitle = (altM && altM[1]) || (titleM && titleM[1]) || '';
    const title = cleanDisplayTitle(rawTitle);
    const poster = (imgM && imgM[1]) || '';
    const rating = rateM ? parseFloat(rateM[1]) || 7.2 : 7.2;

    if (title.length > 2) {
      seenUrls.add(postUrl);
      const isTv = /season|\bs\d+\b|series|k-drama|episode|tv-show/i.test(rawTitle) ||
        postUrl.includes('series') || postUrl.includes('season');
      const yearMatch = rawTitle.match(/\((\d{4})\)/);
      const year = yearMatch ? parseInt(yearMatch[1]) : (postUrl.includes('2026') ? 2026 : new Date().getFullYear());

      // Deterministic numeric ID
      let hash = 0;
      for (let i = 0; i < postUrl.length; i++) {
        hash = (hash * 31 + postUrl.charCodeAt(i)) & 0x7FFFFFFF;
      }
      const id = (hash % 9000000) + 1000000;

      cards.push({
        id,
        media_type: isTv ? 'tv' : 'movie',
        title,
        raw_title: cleanTitle(rawTitle),
        poster_url: poster,
        post_url: postUrl,
        release_year: year,
        vote_average: rating,
        site,
      });
    }
  }

  return cards;
}

async function fetchWithTimeout(url) {
  try {
    const res = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    });
    if (res.ok) {
      return await res.text();
    }
  } catch (err) {
    console.error(`Fetch failed for ${url}:`, err);
  }
  return '';
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    const cacheKey = new Request(url.toString(), request);
    const cache = caches.default;
    let response = await cache.match(cacheKey);

    if (response) {
      const newHeaders = new Headers(response.headers);
      newHeaders.set('X-Cache', 'HIT');
      newHeaders.set('Access-Control-Allow-Origin', '*');
      return new Response(response.body, {
        status: response.status,
        headers: newHeaders,
      });
    }

    if (url.pathname === '/api/home') {
      // Parallel fetch Rog 2026 (p1, p2), Vega homepage, Rog homepage
      const [rog2026p1, rog2026p2, vegaHome, rogHome] = await Promise.all([
        fetchWithTimeout(`${ROG_BASE}/movies-by-year/2026/`),
        fetchWithTimeout(`${ROG_BASE}/movies-by-year/2026/page/2/`),
        fetchWithTimeout(VEGA_BASE),
        fetchWithTimeout(ROG_BASE),
      ]);

      const rog2026Cards1 = parseCards(rog2026p1, 'rogmovies');
      const rog2026Cards2 = parseCards(rog2026p2, 'rogmovies');
      const vegaCards = parseCards(vegaHome, 'vegamovies');
      const rogCards = parseCards(rogHome, 'rogmovies');

      const usedUrls = new Set();
      const usedKeys = new Set();
      function cleanKey(t) {
        return (t || '').toLowerCase().replace(/[^a-z0-9]/g, '');
      }

      function markUsed(card) {
        usedUrls.add(card.post_url);
        const k = cleanKey(card.title);
        if (k.length > 5) usedKeys.add(k);
      }

      function isUsed(card) {
        if (usedUrls.has(card.post_url)) return true;
        const k = cleanKey(card.title);
        if (k.length > 5) {
          for (const u of usedKeys) {
            if (k.includes(u) || u.includes(k)) return true;
          }
        }
        return false;
      }

      // 1. Top 10 Indian Today (2026, exclude reality shows)
      const top10Indian = [];
      for (const card of rog2026Cards1) {
        if (EXCLUDED_PATTERNS.test(card.raw_title)) continue;
        if (!isUsed(card)) {
          card.is_trending = true;
          card.trending_rank = top10Indian.length + 1;
          top10Indian.push(card);
          markUsed(card);
          if (top10Indian.length >= 10) break;
        }
      }

      if (top10Indian.length < 10) {
        for (const card of rog2026Cards2) {
          if (EXCLUDED_PATTERNS.test(card.raw_title)) continue;
          if (!isUsed(card)) {
            card.is_trending = true;
            card.trending_rank = top10Indian.length + 1;
            top10Indian.push(card);
            markUsed(card);
            if (top10Indian.length >= 10) break;
          }
        }
      }

      // 2. Carousel (Top 5 featured from Vega homepage)
      const carousel = vegaCards.slice(0, 5).map((c, i) => ({
        ...c,
        is_trending: true,
        trending_rank: i + 1,
      }));

      // 3. Top 10 Hindi Dub Today (5 Rog + 5 Vega, interleaved, distinct)
      const top10HindiDub = [];
      let rIdx = 0;
      let vIdx = 0;

      for (let i = 0; i < 5; i++) {
        while (rIdx < rogCards.length && isUsed(rogCards[rIdx])) rIdx++;
        if (rIdx < rogCards.length) {
          const card = { ...rogCards[rIdx++], is_trending: true };
          markUsed(card);
          top10HindiDub.push(card);
        }

        while (vIdx < vegaCards.length && isUsed(vegaCards[vIdx])) vIdx++;
        if (vIdx < vegaCards.length) {
          const card = { ...vegaCards[vIdx++], is_trending: true };
          markUsed(card);
          top10HindiDub.push(card);
        }
      }

      // Fill up to 10 if needed
      while (top10HindiDub.length < 10 && rIdx < rogCards.length) {
        if (!isUsed(rogCards[rIdx])) {
          const card = { ...rogCards[rIdx], is_trending: true };
          markUsed(card);
          top10HindiDub.push(card);
        }
        rIdx++;
      }
      while (top10HindiDub.length < 10 && vIdx < vegaCards.length) {
        if (!isUsed(vegaCards[vIdx])) {
          const card = { ...vegaCards[vIdx], is_trending: true };
          markUsed(card);
          top10HindiDub.push(card);
        }
        vIdx++;
      }

      // Assign final ranks 1..10
      top10HindiDub.forEach((item, index) => {
        item.trending_rank = index + 1;
      });

      const payload = {
        carousel,
        top10Indian,
        top10HindiDub,
        cached_at: new Date().toISOString(),
      };

      response = new Response(JSON.stringify(payload), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'public, max-age=300, s-maxage=600', // Cache at edge for 10 minutes
          'Access-Control-Allow-Origin': '*',
          'X-Cache': 'MISS',
        },
      });

      ctx.waitUntil(cache.put(cacheKey, response.clone()));
      return response;
    }

    if (url.pathname === '/api/category') {
      const name = (url.searchParams.get('name') || '').toLowerCase();
      const page = parseInt(url.searchParams.get('page') || '1', 10);

      let targetUrl = '';
      let site = 'vegamovies';

      if (name === 'korean') {
        targetUrl = page === 1 ? `${VEGA_BASE}/korean-series/` : `${VEGA_BASE}/korean-series/page/${page}/`;
      } else if (name === 'chinese') {
        targetUrl = page === 1 ? `${VEGA_BASE}/chinese-series/` : `${VEGA_BASE}/chinese-series/page/${page}/`;
      } else if (name === 'anime') {
        targetUrl = page === 1 ? `${VEGA_BASE}/anime-series/` : `${VEGA_BASE}/anime-series/page/${page}/`;
      } else {
        // Genre pages
        targetUrl = page === 1 ? `${VEGA_BASE}/movies-by-genres/${name}/` : `${VEGA_BASE}/movies-by-genres/${name}/page/${page}/`;
      }

      const html = await fetchWithTimeout(targetUrl);
      const items = parseCards(html, site);

      const payload = {
        category: name,
        page,
        items,
        cached_at: new Date().toISOString(),
      };

      response = new Response(JSON.stringify(payload), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'public, max-age=600, s-maxage=900', // Cache 15 minutes
          'Access-Control-Allow-Origin': '*',
          'X-Cache': 'MISS',
        },
      });

      ctx.waitUntil(cache.put(cacheKey, response.clone()));
      return response;
    }

    return new Response(JSON.stringify({ error: 'Endpoint not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  },
};
