const fs = require('fs');
const path = require('path');

const VEGA_BASE = 'https://vegamovies.gallery';
const ROG_BASE = 'https://rogmovies.wtf';

const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
};

const EXCLUDED_PATTERNS = /roadies|bigg?\s*boss|dance\s*master|hustle|top\s*1\s*%|top\s*1\s*percent|sa\s*re\s*ga\s*ma|sare\s*gama|best\s*dancer|beat\s*dancer|khatron\s*ke\s*khiladi|got\s*latent|kapil\s*show|reality|tv-show|rise\s*and\s*fall|family\s*full\s*house|indian\s*idol|splitsvilla|super\s*singer|masterchef|voice\s*of\s*india|jhalak\s*dikhhla\s*jaa|nach\s*baliye|comedy\s*circus|laughter\s*challenge|fear\s*factor|lock\s*upp|temptation\s*island|talent\s*hunt|competition/i;

function cleanTitle(raw) {
  if (!raw) return '';
  return raw
    .replace(/&#038;|&amp;/gi, '&')
    .replace(/&#8211;/gi, '-')
    .replace(/&#8217;/gi, "'")
    .replace(/&#8216;/gi, "'")
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
  t = t.replace(/\s*\((?:Season|\d{4}|S\d+|Episode).*?\)/gi, ' ');
  t = t.replace(/\s*[-–]\s*Season\s*\d+/gi, ' ');
  t = t.replace(/\s*\(\d{4}\)/g, ' ');
  t = t.replace(/\s*[:\-–]\s*(?:English|Hindi|Dual|Multi|Tamil|Telugu|Punjabi|Season|Substitle|Subtitle|Episode).*$/gi, '');
  t = t.replace(/\s*(?:Full Movie|Complete Web Series|WEB-Series|Anime Series|TV-Show|Full Indian Show|Full WWE Show|WEB-DL|WeB-DL|HDTC|PreDVD|HDRip|BluRay|x264|x265|HEVC|H\.264|HQ|UnCut|ORG\.?|LiNE|Hindi|Dual Audio|Multi-Audio|Tamil|Telugu|Punjabi|JHS|Sony-Liv|SonyLiv|Netflix|AMZN|Zee5|JioHotstar|–|\*No Ads\*|480p|720p|1080p|2160p|10Bit).*$/gi, '');
  t = t.replace(/\s*\(\d{4}\)/g, '');
  t = t.replace(/\s+/g, ' ').trim();
  return t.length >= 2 ? t : cleanTitle(raw);
}

function parseCards(html, site) {
  const cards = [];
  const seenUrls = new Set();
  const cardRegex = /<div class="poster-card"[^>]*>([\s\S]*?)(?=<div class="poster-card"|<\/section>|<\/main>|<nav class="pagination"|$)/gi;
  const urlRegex = /<meta itemprop="url" content="([^"]+)"|href="([^"]+)"/i;
  const imgRegex = /<img[^>]+(?:src|data-src)="([^"]+)"/i;
  const altRegex = /alt="([^"]+)"/i;
  const titleTagRegex = /class="poster-title"[^>]*>([\s\S]*?)<\/(?:p|div|h\d)>/i;
  const rateRegex = /itemprop="ratingValue" content="([^"]+)"|imdb-score[^>]*>[^\d]*(\d+\.?\d*)/i;
  const timeRegex = /<time[^>]*datetime="([^"]+)"/i;

  let match;
  while ((match = cardRegex.exec(html)) !== null) {
    const block = match[1] || '';
    const urlM = block.match(urlRegex);
    const postUrl = urlM ? (urlM[1] || urlM[2]) : null;
    if (!postUrl || seenUrls.has(postUrl)) continue;

    const imgM = block.match(imgRegex);
    const altM = block.match(altRegex);
    const titleTagM = block.match(titleTagRegex);
    const rateM = block.match(rateRegex);
    const timeM = block.match(timeRegex);

    let rawTitle = '';
    if (titleTagM) {
      rawTitle = titleTagM[1].replace(/<[^>]+>/g, '').trim();
    }
    if (!rawTitle && altM) {
      rawTitle = altM[1];
    }
    const title = cleanTitle(rawTitle);
    if (title.length < 2) continue;

    const poster = imgM ? imgM[1] : '';
    const ratingVal = rateM ? (rateM[1] || rateM[2]) : null;
    const rating = ratingVal ? parseFloat(ratingVal) || 7.2 : 7.2;
    const datePublished = timeM ? timeM[1] : null;

    seenUrls.add(postUrl);
    cards.push({
      site,
      postUrl,
      posterUrl: poster,
      title,
      rawTitle,
      rating,
      datePublished,
    });
  }

  return cards;
}

function createManifestItem(card, { isTrending = false, trendingRank = null, categoryTag = null, localDbMap = null } = {}) {
  const displayTitle = cleanDisplayTitle(card.title);
  const isTv = /season|\bs\d+\b|series|k-drama|episode|tv-show/i.test(card.title) ||
    card.postUrl.includes('series') || card.postUrl.includes('season');

  let year = null;
  const yearMatch = card.title.match(/\((\d{4})\)/);
  if (yearMatch) {
    year = parseInt(yearMatch[1], 10);
  } else if (card.postUrl.includes('2026')) {
    year = 2026;
  } else if (card.datePublished) {
    year = new Date(card.datePublished).getFullYear();
  } else {
    year = 2026;
  }

  // Fast deterministic hash ID
  let hash = 0;
  for (let i = 0; i < card.postUrl.length; i++) {
    hash = (hash * 31 + card.postUrl.charCodeAt(i)) & 0x7FFFFFFF;
  }
  let id = (hash % 9000000) + 1000000;

  const langSet = new Set();
  const countrySet = new Set();
  const genreSet = new Set();
  const genreIdSet = new Set();
  let origLang = null;
  let imdbId = null;
  let tmdbPosterPath = null;

  if (categoryTag) {
    const tag = categoryTag.toLowerCase().trim();
    if (tag === 'korean' || tag === 'k-drama' || tag === 'kdrama') {
      langSet.add('Korean');
      countrySet.add('KR');
      origLang = 'ko';
    } else if (tag === 'chinese') {
      langSet.add('Chinese');
      countrySet.add('CN');
      origLang = 'zh';
    } else if (tag === 'anime') {
      genreSet.add('Animation');
      genreSet.add('Anime');
      genreIdSet.add(16);
      countrySet.add('JP');
    } else if (tag === 'indian' || tag === 'bollywood') {
      langSet.add('Hindi');
      countrySet.add('IN');
      origLang = 'hi';
    } else if (tag === 'dual-audio' || tag === 'dualaudio') {
      langSet.add('Hindi');
      langSet.add('English');
      langSet.add('Dual Audio');
    } else if (tag !== 'all' && tag !== 'explore' && tag !== 'search') {
      genreSet.add(tag.charAt(0).toUpperCase() + tag.slice(1));
    }
  }

  const lowerTitle = card.title.toLowerCase();
  if (lowerTitle.includes('hindi')) langSet.add('Hindi');
  if (lowerTitle.includes('english')) langSet.add('English');
  if (lowerTitle.includes('korean')) {
    langSet.add('Korean');
    countrySet.add('KR');
    origLang = origLang || 'ko';
  }
  if (lowerTitle.includes('chinese')) {
    langSet.add('Chinese');
    countrySet.add('CN');
    origLang = origLang || 'zh';
  }
  if (lowerTitle.includes('dual audio') || lowerTitle.includes('dubbed')) {
    langSet.add('Dual Audio');
    langSet.add('Hindi');
  }

  // Check if matches local DB item for TMDB ID & extra metadata
  if (localDbMap) {
    const cleanK = displayTitle.toLowerCase().replace(/[^a-z0-9]/g, '');
    const matched = localDbMap.get(cleanK);
    if (matched) {
      if (matched.id) id = matched.id;
      if (matched.imdbId) imdbId = matched.imdbId;
      if (matched.poster) tmdbPosterPath = matched.poster;
      if (matched.genres) matched.genres.forEach(g => genreSet.add(g));
      if (matched.languages) matched.languages.forEach(l => langSet.add(l));
      if (matched.countries) matched.countries.forEach(c => countrySet.add(c));
    }
  }

  return {
    id,
    media_type: isTv ? 'tv' : 'movie',
    title: displayTitle,
    raw_title: card.title,
    poster_url: card.posterUrl || null,
    backdrop_url: card.posterUrl || null,
    vote_average: card.rating || 7.2,
    vote_count: 0,
    release_year: year,
    original_language: origLang,
    origin_country: Array.from(countrySet),
    genre_ids: Array.from(genreIdSet),
    genres: Array.from(genreSet),
    overview: null,
    tagline: null,
    runtime: null,
    number_of_seasons: isTv ? 1 : null,
    number_of_episodes: null,
    status: null,
    imdb_id: imdbId,
    language: Array.from(langSet),
    result: null,
    is_trending: isTrending,
    is_popular: false,
    trending_rank: trendingRank,
    tmdb_poster_path: tmdbPosterPath,
    tmdb_backdrop_path: null,
    release_date: card.datePublished || `${year}-01-01`,
    post_url: card.postUrl,
  };
}

async function fetchWithRetry(url, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      console.log(`[Fetch] -> ${url} (attempt ${i + 1})`);
      const res = await fetch(url, { headers: HEADERS });
      if (res.ok) {
        return await res.text();
      }
      console.warn(`[Fetch] Non-200 status (${res.status}) for ${url}`);
    } catch (e) {
      console.warn(`[Fetch] Error for ${url}: ${e.message}`);
    }
    await new Promise(r => setTimeout(r, 1000));
  }
  return '';
}

function loadLocalIndices() {
  const map = new Map();
  try {
    const rogPath = path.join(__dirname, '..', 'assets', 'rog_index.json');
    const vegaPath = path.join(__dirname, '..', 'assets', 'vega_index.json');

    function processIndex(filePath) {
      if (!fs.existsSync(filePath)) return;
      const raw = fs.readFileSync(filePath, 'utf8');
      const list = JSON.parse(raw);
      for (const item of list) {
        if (!Array.isArray(item)) continue;
        const [id, title, type, origLang, countries, langs, genres, imdbId, date] = item;
        const clean = cleanDisplayTitle(title).toLowerCase().replace(/[^a-z0-9]/g, '');
        if (clean.length > 2 && !map.has(clean)) {
          map.set(clean, {
            id,
            title,
            type,
            origLang,
            countries: Array.isArray(countries) ? countries : [],
            languages: Array.isArray(langs) ? langs : [],
            genres: Array.isArray(genres) ? genres : [],
            imdbId,
            date,
          });
        }
      }
    }

    processIndex(rogPath);
    processIndex(vegaPath);
    console.log(`[LocalIndex] Loaded ${map.size} indexed titles for fast enrichment`);
  } catch (e) {
    console.warn('[LocalIndex] Error loading indices:', e.message);
  }
  return map;
}

async function main() {
  console.log('=== Starting Rogmovies & Vegamovies Data Extraction ===');
  const localDbMap = loadLocalIndices();

  // 1. Fetch Home Sources
  console.log('\n--- 1. Fetching Home Screen Pages ---');
  const [rog2026Html1, rog2026Html2, vegaHomeHtml, rogHomeHtml] = await Promise.all([
    fetchWithRetry(`${ROG_BASE}/movies-by-year/2026/`),
    fetchWithRetry(`${ROG_BASE}/movies-by-year/2026/page/2/`),
    fetchWithRetry(VEGA_BASE),
    fetchWithRetry(ROG_BASE),
  ]);

  const rog2026Cards1 = parseCards(rog2026Html1, 'rogmovies');
  const rog2026Cards2 = parseCards(rog2026Html2, 'rogmovies');
  const vegaCards = parseCards(vegaHomeHtml, 'vegamovies');
  const rogCards = parseCards(rogHomeHtml, 'rogmovies');

  console.log(`Parsed cards: Rog 2026 p1=${rog2026Cards1.length}, p2=${rog2026Cards2.length}, Vega=${vegaCards.length}, Rog=${rogCards.length}`);

  const usedUrls = new Set();
  const usedTitles = new Set();
  function cleanKey(t) {
    return (t || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  }

  function markUsed(card) {
    usedUrls.add(card.postUrl);
    const k = cleanKey(card.title);
    if (k.length > 5) usedTitles.add(k);
  }

  function isUsed(card) {
    if (usedUrls.has(card.postUrl)) return true;
    const k = cleanKey(card.title);
    if (k.length > 5) {
      for (const u of usedTitles) {
        if (k.includes(u) || u.includes(k)) return true;
      }
    }
    return false;
  }

  // A. Top 10 Indian Today
  const top10Indian = [];
  for (const card of rog2026Cards1) {
    if (EXCLUDED_PATTERNS.test(card.title)) continue;
    if (!isUsed(card)) {
      top10Indian.push(createManifestItem(card, {
        isTrending: true,
        trendingRank: top10Indian.length + 1,
        categoryTag: 'indian',
        localDbMap,
      }));
      markUsed(card);
      if (top10Indian.length >= 10) break;
    }
  }

  if (top10Indian.length < 10) {
    for (const card of rog2026Cards2) {
      if (EXCLUDED_PATTERNS.test(card.title)) continue;
      if (!isUsed(card)) {
        top10Indian.push(createManifestItem(card, {
          isTrending: true,
          trendingRank: top10Indian.length + 1,
          categoryTag: 'indian',
          localDbMap,
        }));
        markUsed(card);
        if (top10Indian.length >= 10) break;
      }
    }
  }

  // B. Carousel: Top 5 featured from Vega homepage
  const carousel = vegaCards.slice(0, 5).map((card, i) => {
    return createManifestItem(card, {
      isTrending: true,
      trendingRank: i + 1,
      localDbMap,
    });
  });
  carousel.forEach(c => usedUrls.add(c.post_url));

  // C. Top 10 Hindi Dub Today: 5 Rog + 5 Vega
  const top10HindiDub = [];
  let rIdx = 0;
  let vIdx = 0;

  for (let i = 0; i < 5; i++) {
    while (rIdx < rogCards.length && isUsed(rogCards[rIdx])) rIdx++;
    if (rIdx < rogCards.length) {
      const card = rogCards[rIdx++];
      markUsed(card);
      top10HindiDub.push(createManifestItem(card, {
        isTrending: true,
        categoryTag: 'dual-audio',
        localDbMap,
      }));
    }

    while (vIdx < vegaCards.length && isUsed(vegaCards[vIdx])) vIdx++;
    if (vIdx < vegaCards.length) {
      const card = vegaCards[vIdx++];
      markUsed(card);
      top10HindiDub.push(createManifestItem(card, {
        isTrending: true,
        categoryTag: 'dual-audio',
        localDbMap,
      }));
    }
  }

  while (top10HindiDub.length < 10 && rIdx < rogCards.length) {
    if (!isUsed(rogCards[rIdx])) {
      const card = rogCards[rIdx];
      markUsed(card);
      top10HindiDub.push(createManifestItem(card, {
        isTrending: true,
        categoryTag: 'dual-audio',
        localDbMap,
      }));
    }
    rIdx++;
  }

  while (top10HindiDub.length < 10 && vIdx < vegaCards.length) {
    if (!isUsed(vegaCards[vIdx])) {
      const card = vegaCards[vIdx];
      markUsed(card);
      top10HindiDub.push(createManifestItem(card, {
        isTrending: true,
        categoryTag: 'dual-audio',
        localDbMap,
      }));
    }
    vIdx++;
  }

  top10HindiDub.forEach((item, index) => {
    item.trending_rank = index + 1;
  });

  console.log(`\nHome sections compiled: Top10 Indian = ${top10Indian.length}, Carousel = ${carousel.length}, Top10 Hindi Dub = ${top10HindiDub.length}`);

  // 2. Fetch Category Sections
  console.log('\n--- 2. Fetching Category Pages ---');
  const categoryUrls = {
    'korean': `${VEGA_BASE}/korean-series/`,
    'chinese': `${VEGA_BASE}/chinese-series/`,
    'anime': `${VEGA_BASE}/anime-series/`,
    'action': `${VEGA_BASE}/movies-by-genres/action/`,
    'sci-fi': `${VEGA_BASE}/movies-by-genres/sci-fi/`,
    'comedy': `${VEGA_BASE}/movies-by-genres/comedy/`,
    'thriller': `${VEGA_BASE}/movies-by-genres/thriller/`,
    'horror': `${VEGA_BASE}/movies-by-genres/horror/`,
    'romance': `${VEGA_BASE}/movies-by-genres/romance/`,
    'adventure': `${VEGA_BASE}/movies-by-genres/adventure/`,
    'crime': `${VEGA_BASE}/movies-by-genres/crime/`,
    'drama': `${VEGA_BASE}/movies-by-genres/drama/`,
    'mystery': `${VEGA_BASE}/movies-by-genres/mystery/`,
    'fantasy': `${VEGA_BASE}/movies-by-genres/fantasy/`,
    'animation': `${VEGA_BASE}/movies-by-genres/animation/`,
    'dual-audio': `${VEGA_BASE}/`,
    'indian': `${ROG_BASE}/movies-by-year/2026/`,
    'bollywood': `${ROG_BASE}/`,
    'all': `${VEGA_BASE}/`,
    'hollywood': `${VEGA_BASE}/?s=Hollywood`,
    'punjabi': `${VEGA_BASE}/?s=Punjabi`,
    'pakistani': `${VEGA_BASE}/?s=Pakistani`,
  };

  const cats = {};

  for (const [slug, url] of Object.entries(categoryUrls)) {
    const site = (slug === 'indian' || slug === 'bollywood') ? 'rogmovies' : 'vegamovies';
    const html = await fetchWithRetry(url);
    const cards = parseCards(html, site);
    const items = cards.map(c => createManifestItem(c, { categoryTag: slug, localDbMap }));
    cats[slug] = items;
    console.log(`Category "${slug}": extracted ${items.length} items from ${url}`);
  }

  // Backfill categories that got few/no results from direct search
  function backfillFromIndex(targetSlug, predicate) {
    if (cats[targetSlug] && cats[targetSlug].length >= 15) return;
    const existing = cats[targetSlug] || [];
    const existingUrls = new Set(existing.map(e => e.post_url));
    const vegaRaw = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'assets', 'vega_index.json'), 'utf8'));
    const rogRaw = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'assets', 'rog_index.json'), 'utf8'));
    const combined = [...vegaRaw, ...rogRaw];
    const added = [];

    for (const row of combined) {
      if (!Array.isArray(row)) continue;
      const [id, title, type, origLang, countries, langs, genres, imdbId, date] = row;
      const cList = Array.isArray(countries) ? countries : [];
      const lList = Array.isArray(langs) ? langs : [];
      const gList = Array.isArray(genres) ? genres : [];
      
      if (predicate({ id, title, type, origLang, countries: cList, languages: lList, genres: gList, date })) {
        const fakeCard = {
          site: 'vegamovies',
          postUrl: `https://vegamovies.gallery/?p=${id}`,
          posterUrl: `https://image.tmdb.org/t/p/w500/${id}.jpg`,
          title,
          rawTitle: title,
          rating: 7.5,
          datePublished: date,
        };
        const item = createManifestItem(fakeCard, { categoryTag: targetSlug, localDbMap });
        if (!existingUrls.has(item.post_url)) {
          existingUrls.add(item.post_url);
          added.push(item);
          if (existing.length + added.length >= 20) break;
        }
      }
    }
    cats[targetSlug] = [...existing, ...added];
    console.log(`Backfilled category "${targetSlug}": total ${cats[targetSlug].length} items`);
  }

  backfillFromIndex('hollywood', item => item.origLang === 'en' || item.languages.includes('English') || item.countries.includes('US'));
  backfillFromIndex('punjabi', item => item.languages.includes('Punjabi') || item.title.toLowerCase().includes('punjabi'));
  backfillFromIndex('pakistani', item => item.countries.includes('PK') || item.languages.includes('Urdu') || item.title.toLowerCase().includes('pakistani'));

  // Ensure search and explore fallbacks exist
  cats['search'] = cats['all'] || cats['dual-audio'] || [];
  cats['explore'] = cats['all'] || cats['dual-audio'] || [];

  // 3. Assemble and Write base_home.json (HOMEPAGE ONLY for 0ms instant startup)
  const homePayload = {
    timestamp: new Date().toISOString(),
    home: {
      carousel,
      top10Indian,
      top10HindiDub,
      top5: carousel,
      top10: top10HindiDub,
      timestamp: new Date().toISOString(),
    },
  };

  const outputPath = path.join(__dirname, '..', 'assets', 'base_home.json');
  fs.writeFileSync(outputPath, JSON.stringify(homePayload, null, 2), 'utf8');
  console.log(`\nSUCCESS! Wrote base home JSON to: ${outputPath} (${(fs.statSync(outputPath).size / 1024).toFixed(1)} KB)`);

  // 4. Write Individual Category JSON Files (assets/categories/*.json)
  const catsDir = path.join(__dirname, '..', 'assets', 'categories');
  if (!fs.existsSync(catsDir)) {
    fs.mkdirSync(catsDir, { recursive: true });
  }

  for (const [slug, items] of Object.entries(cats)) {
    const catPath = path.join(catsDir, `${slug}.json`);
    fs.writeFileSync(catPath, JSON.stringify(items, null, 2), 'utf8');
    console.log(`  -> Wrote category "${slug}" (${items.length} items) to: ${catPath}`);
  }
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
