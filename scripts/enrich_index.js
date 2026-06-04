/**
 * Enrich index.json with release_date from TMDB API.
 * 
 * Usage: node scripts/enrich_index.js
 * 
 * What it does:
 *   1. Reads index.json
 *   2. For each item with a numeric TMDB ID that lacks release_date:
 *      - Fetches movie/tv details from TMDB
 *      - Extracts release_date (movies) or first_air_date (TV)
 *   3. Preserves any existing release_date (from streaming_links files)
 *   4. Writes enriched index.json + copies to assets/base_index.json
 *   5. Also enriches original_language, origin_country, genres if missing
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const TMDB_API_KEY = 'fc6d85b3839330e3458701b975195487';
const TMDB_BASE = 'https://api.themoviedb.org/3';
const CONCURRENCY = 8; // Parallel requests
const RATE_LIMIT_DELAY = 300; // ms between batches (TMDB: ~40 req/10s)

// Genre ID → name mapping from TMDB
const GENRE_MAP = {
  28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy',
  80: 'Crime', 99: 'Documentary', 18: 'Drama', 10751: 'Family',
  14: 'Fantasy', 36: 'History', 27: 'Horror', 10402: 'Music',
  9648: 'Mystery', 10749: 'Romance', 878: 'Science Fiction',
  53: 'Thriller', 10752: 'War', 37: 'Western',
  // TV genres
  10759: 'Action & Adventure', 10762: 'Kids', 10763: 'News',
  10764: 'Reality', 10765: 'Sci-Fi & Fantasy', 10766: 'Soap',
  10767: 'Talk', 10768: 'War & Politics',
};

function tmdbFetch(urlPath) {
  return new Promise((resolve, reject) => {
    const url = `${TMDB_BASE}${urlPath}${urlPath.includes('?') ? '&' : '?'}api_key=${TMDB_API_KEY}&language=en-US`;
    
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            resolve(null);
          }
        } else if (res.statusCode === 404) {
          resolve(null); // Item not found on TMDB
        } else if (res.statusCode === 429) {
          // Rate limited — wait and retry
          setTimeout(() => {
            tmdbFetch(urlPath).then(resolve).catch(reject);
          }, 2000);
        } else {
          resolve(null);
        }
      });
      res.on('error', () => resolve(null));
    }).on('error', () => resolve(null));
  });
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function enrichItem(item) {
  const id = item.id;
  const type = item.type || 'movie';
  
  // Skip non-numeric IDs (ULIDs — not in TMDB)
  if (!/^\d+$/.test(String(id))) {
    return item;
  }
  
  // Check what's missing
  const needsReleaseDate = !item.release_date || item.release_date === '';
  const needsGenres = !item.genres || item.genres.length === 0;
  const needsOrigLang = !item.original_language || item.original_language === '' || item.original_language === 'en';
  const needsCountry = !item.country || item.country.length === 0;
  
  // Skip if everything is already populated
  if (!needsReleaseDate && !needsGenres) {
    return item;
  }
  
  try {
    const endpoint = type === 'tv' ? `/tv/${id}` : `/movie/${id}`;
    const data = await tmdbFetch(endpoint);
    
    if (!data) return item;
    
    const enriched = { ...item };
    
    // release_date: use streaming_links value if present, else TMDB
    if (needsReleaseDate) {
      const tmdbDate = type === 'tv' 
        ? (data.first_air_date || '') 
        : (data.release_date || '');
      if (tmdbDate) {
        enriched.release_date = tmdbDate;
      }
    }
    
    // genres: convert genre IDs to names
    if (needsGenres && data.genres) {
      enriched.genres = data.genres.map(g => g.name).filter(Boolean);
    }
    
    // original_language
    if (needsOrigLang && data.original_language) {
      enriched.original_language = data.original_language;
    }
    
    // origin_country
    if (needsCountry) {
      const countries = data.origin_country || 
        (data.production_countries || []).map(c => c.iso_3166_1);
      if (countries && countries.length > 0) {
        enriched.country = countries;
      }
    }
    
    // imdb_id
    if ((!enriched.imdb_id || enriched.imdb_id === '') && data.imdb_id) {
      enriched.imdb_id = data.imdb_id;
    }
    
    return enriched;
  } catch (e) {
    return item;
  }
}

async function processBatch(items, startIdx) {
  const batch = items.slice(startIdx, startIdx + CONCURRENCY);
  const results = await Promise.all(batch.map(enrichItem));
  return results;
}

async function main() {
  const indexPath = path.resolve(__dirname, '..', 'index.json');
  const baseIndexPath = path.resolve(__dirname, '..', 'assets', 'base_index.json');
  
  console.log('📖 Reading index.json...');
  const rawData = fs.readFileSync(indexPath, 'utf8');
  const indexData = JSON.parse(rawData);
  const posts = indexData.posts || [];
  
  console.log(`📊 Total items: ${posts.length}`);
  
  // Count items needing enrichment
  const needsEnrichment = posts.filter(p => {
    const isNumeric = /^\d+$/.test(String(p.id));
    const needsDate = !p.release_date || p.release_date === '';
    const needsGenres = !p.genres || p.genres.length === 0;
    return isNumeric && (needsDate || needsGenres);
  });
  
  console.log(`🔍 Items needing TMDB enrichment: ${needsEnrichment.length}`);
  console.log(`⏭️  Items already complete or non-TMDB: ${posts.length - needsEnrichment.length}`);
  
  // Process all items
  const enrichedPosts = [];
  let processed = 0;
  let enriched = 0;
  let failed = 0;
  
  for (let i = 0; i < posts.length; i += CONCURRENCY) {
    const batch = posts.slice(i, i + CONCURRENCY);
    const results = await Promise.all(batch.map(enrichItem));
    
    for (let j = 0; j < results.length; j++) {
      enrichedPosts.push(results[j]);
      const original = batch[j];
      if (results[j].release_date && !original.release_date) {
        enriched++;
      }
    }
    
    processed += batch.length;
    
    if (processed % 100 === 0 || processed === posts.length) {
      console.log(`  ✅ ${processed}/${posts.length} processed (${enriched} enriched)`);
    }
    
    // Rate limit: wait between batches
    if (i + CONCURRENCY < posts.length) {
      await sleep(RATE_LIMIT_DELAY);
    }
  }
  
  console.log(`\n📝 Enrichment complete:`);
  console.log(`   - ${enriched} items enriched with release_date`);
  console.log(`   - ${posts.length - enriched} items unchanged`);
  
  // Write enriched index.json
  const output = {
    last_updated: new Date().toISOString(),
    total: enrichedPosts.length,
    posts: enrichedPosts,
  };
  
  const outputJson = JSON.stringify(output, null, 2);
  
  fs.writeFileSync(indexPath, outputJson, 'utf8');
  console.log(`\n💾 Written enriched index.json (${(Buffer.byteLength(outputJson) / 1024 / 1024).toFixed(2)} MB)`);
  
  // Copy to assets/base_index.json
  fs.writeFileSync(baseIndexPath, outputJson, 'utf8');
  console.log(`📋 Copied to assets/base_index.json`);
  
  console.log('\n🎉 Done! Rebuild the app to use the enriched data.');
}

main().catch(e => {
  console.error('❌ Error:', e);
  process.exit(1);
});
