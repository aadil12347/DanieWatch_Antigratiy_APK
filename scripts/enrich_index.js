/**
 * Enrich and convert index.json to positional array format.
 * 
 * Usage: node scripts/enrich_index.js
 * 
 * Positional array structure:
 *   [
 *     id,                 // 0: String/Int ID
 *     title,              // 1: Movie/Show title
 *     type,               // 2: "movie" or "tv"
 *     original_language,  // 3: ISO 639-1 code
 *     country,            // 4: List of origin countries (e.g. ["IN"])
 *     language,           // 5: Dubbed/audio languages (e.g. ["Hindi", "English"])
 *     genres,             // 6: List of TMDB Genre IDs (e.g. [18, 28])
 *     imdb_id,            // 7: IMDb ID (e.g. "tt1234567")
 *     release_date        // 8: "YYYY-MM-DD"
 *   ]
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const TMDB_API_KEY = 'fc6d85b3839330e3458701b975195487';
const TMDB_BASE = 'https://api.themoviedb.org/3';
const CONCURRENCY = 8; // Parallel requests
const RATE_LIMIT_DELAY = 150; // ms between batches

// Genre ID ↔ name mapping from TMDB
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

const REVERSE_GENRE_MAP = {};
for (const [id, name] of Object.entries(GENRE_MAP)) {
  REVERSE_GENRE_MAP[name.toLowerCase()] = parseInt(id, 10);
}
// Add some alias mappings
REVERSE_GENRE_MAP['science fiction'] = 878;
REVERSE_GENRE_MAP['sci-fi'] = 878;
REVERSE_GENRE_MAP['action & adventure'] = 10759;
REVERSE_GENRE_MAP['sci-fi & fantasy'] = 10765;
REVERSE_GENRE_MAP['war & politics'] = 10768;

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

// Global list to collect failed fetches
const failedFetches = [];

async function enrichItem(item) {
  // item is in positional array format:
  // [id, title, type, original_language, country, language, genres, imdb_id, release_date]
  const id = item[0];
  const title = item[1];
  const type = item[2] || 'movie';
  
  // Skip non-numeric IDs (ULIDs / IMDb IDs in TMDB ID spot)
  if (!/^\d+$/.test(String(id))) {
    return item;
  }
  
  const needsReleaseDate = !item[8] || item[8] === '';
  const needsGenres = !item[6] || item[6].length === 0;
  const needsOrigLang = !item[3] || item[3] === '' || item[3] === 'en';
  const needsCountry = !item[4] || item[4].length === 0;
  const needsImdbId = !item[7] || item[7] === '';
  
  // Skip if everything is already populated
  if (!needsReleaseDate && !needsGenres && !needsOrigLang && !needsCountry && !needsImdbId) {
    return item;
  }
  
  try {
    const endpoint = type === 'tv' ? `/tv/${id}` : `/movie/${id}`;
    const data = await tmdbFetch(endpoint);
    
    if (!data) {
      failedFetches.push({ id, title, type, reason: 'Not found on TMDB (404)' });
      return item;
    }
    
    const enriched = [...item];
    
    // 3: original_language
    if (needsOrigLang && data.original_language) {
      enriched[3] = data.original_language;
    }
    
    // 4: country (origin_country)
    if (needsCountry) {
      const countries = data.origin_country || 
        (data.production_countries || []).map(c => c.iso_3166_1);
      if (countries && countries.length > 0) {
        enriched[4] = countries;
      }
    }
    
    // 6: genres (mapped to TMDB genre IDs)
    if (needsGenres && data.genres) {
      enriched[6] = data.genres.map(g => g.id).filter(Boolean);
    }
    
    // 7: imdb_id
    if (needsImdbId) {
      if (data.imdb_id) {
        enriched[7] = data.imdb_id;
      } else if (type === 'tv') {
        // Fetch external IDs for TV shows to get IMDb ID
        const extData = await tmdbFetch(`/tv/${id}/external_ids`);
        if (extData && extData.imdb_id) {
          enriched[7] = extData.imdb_id;
        }
      }
    }

    // 8: release_date
    if (needsReleaseDate) {
      const tmdbDate = type === 'tv' 
        ? (data.first_air_date || '') 
        : (data.release_date || '');
      if (tmdbDate) {
        enriched[8] = tmdbDate;
      }
    }
    
    // If genres or release date are still missing after TMDB call, record as failed
    if (!enriched[6] || enriched[6].length === 0 || !enriched[8] || enriched[8] === '') {
      failedFetches.push({
        id,
        title,
        type,
        reason: `Missing data after TMDB fetch (genres: ${!enriched[6] || enriched[6].length === 0}, date: ${!enriched[8] || enriched[8] === ''})`
      });
    }

    return enriched;
  } catch (e) {
    failedFetches.push({ id, title, type, reason: `Error: ${e.message}` });
    return item;
  }
}

async function main() {
  const indexPath = path.resolve(__dirname, '..', 'index.json');
  
  console.log('📖 Reading index.json...');
  const rawData = fs.readFileSync(indexPath, 'utf8');
  let posts = [];
  
  try {
    const parsed = JSON.parse(rawData);
    if (Array.isArray(parsed)) {
      // Already positional array format
      posts = parsed;
      console.log(`Detected positional array format.`);
    } else if (parsed && parsed.posts) {
      // Old object format: convert to positional arrays
      console.log(`Detected old object format. Mapping to positional arrays...`);
      posts = parsed.posts.map(p => {
        // Map string genres to TMDB IDs
        const genreIds = (p.genres || []).map(g => {
          if (typeof g === 'number') return g;
          return REVERSE_GENRE_MAP[g.toLowerCase()] || null;
        }).filter(Boolean);

        // Standardize release_date: if missing but has year, use YYYY-01-01
        let releaseDate = p.release_date || '';
        if (!releaseDate && p.year) {
          releaseDate = `${p.year}-01-01`;
        }

        return [
          p.id,                                // 0: id
          p.title || '',                       // 1: title
          p.type || 'movie',                   // 2: type
          p.original_language || '',           // 3: original_language
          p.country || [],                     // 4: country
          p.language || [],                    // 5: language
          genreIds,                            // 6: genres (ids)
          p.imdb_id || '',                     // 7: imdb_id
          releaseDate                          // 8: release_date
        ];
      });
    } else {
      throw new Error('Invalid index.json schema');
    }
  } catch (e) {
    console.error('❌ Failed to parse index.json:', e);
    process.exit(1);
  }
  
  console.log(`📊 Total items: ${posts.length}`);
  
  // Count items needing enrichment
  const needsEnrichment = posts.filter(p => {
    const id = p[0];
    const isNumeric = /^\d+$/.test(String(id));
    const needsDate = !p[8] || p[8] === '';
    const needsGenres = !p[6] || p[6].length === 0;
    return isNumeric && (needsDate || needsGenres);
  });
  
  console.log(`🔍 Items needing TMDB enrichment: ${needsEnrichment.length}`);
  console.log(`⏭️  Items already complete or non-TMDB: ${posts.length - needsEnrichment.length}`);
  
  // Process all items
  const enrichedPosts = [];
  let processed = 0;
  let enriched = 0;
  
  for (let i = 0; i < posts.length; i += CONCURRENCY) {
    const batch = posts.slice(i, i + CONCURRENCY);
    const results = await Promise.all(batch.map(enrichItem));
    
    for (let j = 0; j < results.length; j++) {
      enrichedPosts.push(results[j]);
      const original = batch[j];
      // Compare genres count or release date to detect enrichment
      if ((results[j][8] && !original[8]) || (results[j][6].length > original[6].length)) {
        enriched++;
      }
    }
    
    processed += batch.length;
    
    if (processed % 100 === 0 || processed === posts.length) {
      console.log(`  Refreshed: ${processed}/${posts.length} processed (${enriched} enriched)`);
    }
    
    // Rate limit: wait between batches
    if (i + CONCURRENCY < posts.length) {
      await sleep(RATE_LIMIT_DELAY);
    }
  }
  
  console.log(`\n📝 Enrichment complete:`);
  console.log(`   - ${enriched} items enriched`);
  console.log(`   - ${posts.length - enriched} items unchanged`);
  console.log(`   - ${failedFetches.length} items logged in failed fetches`);
  
  // Write failed fetches
  const failedPath = path.resolve(__dirname, '..', 'failed_tmdb_fetches.json');
  fs.writeFileSync(failedPath, JSON.stringify(failedFetches, null, 2), 'utf8');
  console.log(`💾 Saved failed fetches log to ${failedPath}`);
  
  // Write enriched minified index.json (no spaces/indentation to save space)
  const outputJson = JSON.stringify(enrichedPosts);
  fs.writeFileSync(indexPath, outputJson, 'utf8');
  console.log(`💾 Written enriched index.json (${(Buffer.byteLength(outputJson) / 1024 / 1024).toFixed(2)} MB)`);
  
  // Copy to assets/base_index.json (since the app will use this if no sync file is downloaded yet)
  const baseIndexPath = path.resolve(__dirname, '..', 'assets', 'base_index.json');
  fs.writeFileSync(baseIndexPath, outputJson, 'utf8');
  console.log(`📋 Copied to assets/base_index.json`);
  
  console.log('\n🎉 Done!');
}

main().catch(e => {
  console.error('❌ Error:', e);
  process.exit(1);
});
