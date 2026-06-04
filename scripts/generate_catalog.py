#!/usr/bin/env python3
"""
Generate Paginated Catalog from streaming_links + index.json (DanieWatch format).

Pipeline:
  1. Scan streaming_links/ folder (source of truth) + merge with index.json
  2. Fetch exact release dates from TMDB API (cached to avoid re-fetching)
  3. Sort: year DESC → release_date DESC → batch priority → id DESC
  4. Categorize using ONLY origin_country + original_language (NOT dubbing language)
  5. Paginate into catalog/ files

Output:
  catalog/
    meta.json              — version + page counts
    search_index.json      — lightweight search data
    home/sections.json     — pre-built home screen data
    all/page_N.json        — paginated global catalog
    bollywood/page_N.json  — paginated category pages
    ...

Usage:
    python generate_catalog.py [--repo-root .] [--output-dir ./catalog] [--page-size 50]
"""

import json
import os
import sys
import glob
import time
from datetime import datetime, timezone
from typing import Any

# Optional: requests for TMDB API
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False
    print('WARNING: requests not installed — TMDB release date fetching disabled')

PAGE_SIZE = 50

# TMDB API configuration
TMDB_API_KEY = os.environ.get('TMDB_API_KEY', '')
TMDB_BASE = 'https://api.themoviedb.org/3'
TMDB_RATE_LIMIT_DELAY = 0.26  # ~4 requests/sec to stay under TMDB rate limit

# Category matching rules — uses ONLY origin_country + original_language
# NEVER matches on the 'language' field (that's dubbing/audio availability)
CATEGORIES = {
    'bollywood': {
        'countries': ['IN'],
        'languages': ['hi', 'hindi', 'ur', 'urdu', 'pa', 'punjabi', 'ta', 'tamil',
                       'te', 'telugu', 'ml', 'malayalam', 'kn', 'kannada',
                       'bn', 'bengali', 'mr', 'marathi', 'gu', 'gujarati'],
    },
    'korean': {
        'countries': ['KR'],
        'languages': ['ko', 'korean'],
    },
    'anime': {
        'countries': ['JP'],
        'languages': ['ja', 'japanese'],
        'genres': ['Animation'],
    },
    'hollywood': {
        'countries': ['US', 'GB', 'UK', 'AU', 'CA'],
        'languages': ['en', 'english'],
    },
    'chinese': {
        'countries': ['CN', 'HK', 'TW'],
        'languages': ['zh', 'cn', 'chinese', 'mandarin', 'cantonese'],
    },
    'punjabi': {
        'countries': [],
        'languages': ['pa', 'punjabi'],
    },
    'pakistani': {
        'countries': ['PK'],
        'languages': ['ur', 'urdu'],
    },
}

HOME_SECTIONS = [
    {'title': 'Trending Now', 'filter': 'trending', 'limit': 20},
    {'title': 'Top 10 Today', 'filter': 'top10', 'limit': 10, 'is_ranked': True},
    {'title': 'Bollywood', 'filter': 'bollywood', 'limit': 20},
    {'title': 'Korean', 'filter': 'korean', 'limit': 20},
    {'title': 'Anime', 'filter': 'anime', 'limit': 20},
    {'title': 'Hollywood', 'filter': 'hollywood', 'limit': 20},
    {'title': 'Top Rated', 'filter': 'top_rated', 'limit': 20},
    {'title': 'Chinese', 'filter': 'chinese', 'limit': 20},
    {'title': 'Punjabi', 'filter': 'punjabi', 'limit': 20},
    {'title': 'Pakistani', 'filter': 'pakistani', 'limit': 20},
]


# ═══════════════════════════════════════════════════════════════════════════════
# Utility Functions
# ═══════════════════════════════════════════════════════════════════════════════

def safe_int(val) -> int:
    """Parse a value to int, return 0 if not parseable."""
    if val is None:
        return 0
    if isinstance(val, int):
        return val
    try:
        return int(str(val))
    except (ValueError, TypeError):
        return 0


def item_key(item: dict) -> str:
    """Unique key for an item: 'id-type'."""
    tmdb_id = item.get('id') or ''
    media_type = item.get('type') or item.get('media_type', 'movie')
    return f"{tmdb_id}-{media_type}"


# ═══════════════════════════════════════════════════════════════════════════════
# Data Loading
# ═══════════════════════════════════════════════════════════════════════════════

def load_streaming_links(repo_root: str) -> list[dict]:
    """Scan streaming_links/ folder — each JSON file is one movie/show (source of truth)."""
    sl_dir = os.path.join(repo_root, 'streaming_links')
    if not os.path.isdir(sl_dir):
        print(f'  WARNING: streaming_links/ directory not found at {sl_dir}')
        return []
    
    items = []
    errors = 0
    for filepath in glob.glob(os.path.join(sl_dir, '**', '*.json'), recursive=True):
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                item = json.load(f)
                if isinstance(item, dict) and item.get('id'):
                    items.append(item)
                elif isinstance(item, list):
                    # Some files might contain arrays
                    for sub_item in item:
                        if isinstance(sub_item, dict) and sub_item.get('id'):
                            items.append(sub_item)
        except (json.JSONDecodeError, IOError) as e:
            errors += 1
    
    if errors > 0:
        print(f'  WARNING: {errors} files failed to parse in streaming_links/')
    return items


def load_index_json(repo_root: str) -> list[dict]:
    """Load items from index.json (secondary data source)."""
    index_path = os.path.join(repo_root, 'index.json')
    if not os.path.exists(index_path):
        return []
    with open(index_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        return data.get('posts', data.get('items', data.get('results', [])))
    return []


def merge_items(streaming_items: list[dict], index_items: list[dict]) -> list[dict]:
    """Merge streaming_links (priority) with index.json (fallback).
    
    streaming_links data takes priority when both sources have the same item.
    Items in index.json but not in streaming_links are also included.
    """
    merged = {}
    
    # Add index.json items first (lower priority)
    for item in index_items:
        key = item_key(item)
        if key and key != '-movie':  # Skip items without IDs
            merged[key] = item
    
    # Override/add with streaming_links items (higher priority = source of truth)
    for item in streaming_items:
        key = item_key(item)
        if key and key != '-movie':
            if key in merged:
                # Merge: streaming_links fields override, but keep any extra fields from index
                existing = merged[key]
                existing.update(item)
                merged[key] = existing
            else:
                merged[key] = item
    
    return list(merged.values())


def load_posting_record(repo_root: str) -> dict[str, int]:
    """Load posting_record.json for batch ordering."""
    pr_path = os.path.join(repo_root, 'posting_record.json')
    if not os.path.exists(pr_path):
        return {}

    with open(pr_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    priorities: dict[str, int] = {}
    batches = data if isinstance(data, list) else data.get('batches', data.get('items', []))

    if isinstance(batches, list):
        for batch_idx, batch in enumerate(reversed(batches)):
            batch_items = batch.get('items', batch.get('posts', [])) if isinstance(batch, dict) else []
            for item_idx, item in enumerate(batch_items):
                tmdb_id = item.get('tmdb_id') or item.get('id')
                media_type = item.get('type') or item.get('media_type', 'movie')
                if tmdb_id:
                    key = f"{tmdb_id}-{media_type}"
                    if key not in priorities:
                        priorities[key] = batch_idx * 1000 + item_idx

    return priorities


def load_top_content(repo_root: str, folder: str) -> list[dict]:
    """Load Top 5 or Top 10 items."""
    top_dir = os.path.join(repo_root, folder)
    if not os.path.isdir(top_dir):
        return []
    items = []
    for filepath in sorted(glob.glob(os.path.join(top_dir, '*.json'))):
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                items.append(json.load(f))
        except (json.JSONDecodeError, IOError):
            pass
    return items


# ═══════════════════════════════════════════════════════════════════════════════
# TMDB Release Date Fetching
# ═══════════════════════════════════════════════════════════════════════════════

def load_release_date_cache(repo_root: str) -> dict[str, str]:
    """Load cached release dates from release_dates_cache.json."""
    cache_path = os.path.join(repo_root, 'release_dates_cache.json')
    if not os.path.exists(cache_path):
        return {}
    try:
        with open(cache_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


def save_release_date_cache(repo_root: str, cache: dict[str, str]):
    """Save release dates cache."""
    cache_path = os.path.join(repo_root, 'release_dates_cache.json')
    with open(cache_path, 'w', encoding='utf-8') as f:
        json.dump(cache, f, ensure_ascii=False, indent=2, sort_keys=True)


def fetch_movie_release_date(tmdb_id: str) -> str | None:
    """Fetch movie release date from TMDB API."""
    if not HAS_REQUESTS or not TMDB_API_KEY:
        return None
    try:
        resp = requests.get(
            f'{TMDB_BASE}/movie/{tmdb_id}',
            params={'api_key': TMDB_API_KEY},
            timeout=10,
        )
        if resp.status_code == 200:
            return resp.json().get('release_date') or None
        elif resp.status_code == 429:
            # Rate limited — wait and retry once
            time.sleep(2)
            resp = requests.get(
                f'{TMDB_BASE}/movie/{tmdb_id}',
                params={'api_key': TMDB_API_KEY},
                timeout=10,
            )
            if resp.status_code == 200:
                return resp.json().get('release_date') or None
    except Exception:
        pass
    return None


def fetch_tv_release_date(tmdb_id: str, season_num: int, total_eps: int) -> str | None:
    """Fetch TV show release date from TMDB API.
    
    Uses the air_date of the latest uploaded episode as the sorting date.
    """
    if not HAS_REQUESTS or not TMDB_API_KEY:
        return None
    try:
        resp = requests.get(
            f'{TMDB_BASE}/tv/{tmdb_id}/season/{season_num}',
            params={'api_key': TMDB_API_KEY},
            timeout=10,
        )
        if resp.status_code == 200:
            data = resp.json()
            episodes = data.get('episodes', [])
            # Find the latest uploaded episode's air_date
            for ep in reversed(episodes):
                ep_num = ep.get('episode_number', 0)
                if ep_num <= total_eps and ep.get('air_date'):
                    return ep['air_date']
            # Fallback: use season air_date
            return data.get('air_date') or None
        elif resp.status_code == 429:
            time.sleep(2)
            resp = requests.get(
                f'{TMDB_BASE}/tv/{tmdb_id}/season/{season_num}',
                params={'api_key': TMDB_API_KEY},
                timeout=10,
            )
            if resp.status_code == 200:
                data = resp.json()
                episodes = data.get('episodes', [])
                for ep in reversed(episodes):
                    ep_num = ep.get('episode_number', 0)
                    if ep_num <= total_eps and ep.get('air_date'):
                        return ep['air_date']
                return data.get('air_date') or None
        elif resp.status_code == 404:
            # Season not found — try getting the show's first_air_date
            resp2 = requests.get(
                f'{TMDB_BASE}/tv/{tmdb_id}',
                params={'api_key': TMDB_API_KEY},
                timeout=10,
            )
            if resp2.status_code == 200:
                return resp2.json().get('first_air_date') or None
    except Exception:
        pass
    return None


def enrich_with_release_dates(items: list[dict], repo_root: str) -> list[dict]:
    """Fetch release dates from TMDB for all items, using cache to avoid re-fetching."""
    cache = load_release_date_cache(repo_root)
    fetched_count = 0
    cached_count = 0
    failed_count = 0
    
    if not TMDB_API_KEY:
        print('  WARNING: TMDB_API_KEY not set — skipping release date fetching')
        # Still apply cached dates
        for item in items:
            key = item_key(item)
            if key in cache and not item.get('release_date'):
                item['release_date'] = cache[key]
                cached_count += 1
        print(f'  Applied {cached_count} cached release dates')
        return items
    
    total = len(items)
    for i, item in enumerate(items):
        key = item_key(item)
        tmdb_id = str(item.get('id', ''))
        
        if not tmdb_id or safe_int(tmdb_id) <= 0:
            continue
        
        # Check cache first
        if key in cache:
            item['release_date'] = cache[key]
            cached_count += 1
            continue
        
        # Fetch from TMDB
        media_type = item.get('type') or item.get('media_type', 'movie')
        release_date = None
        
        if media_type == 'movie':
            release_date = fetch_movie_release_date(tmdb_id)
        elif media_type in ('tv', 'series'):
            season_num = safe_int(item.get('latest_uploaded_season', 1)) or 1
            total_eps = safe_int(item.get('total_uploaded_episodes', 1)) or 1
            release_date = fetch_tv_release_date(tmdb_id, season_num, total_eps)
        
        if release_date:
            item['release_date'] = release_date
            cache[key] = release_date
            fetched_count += 1
        else:
            failed_count += 1
        
        # Rate limiting
        time.sleep(TMDB_RATE_LIMIT_DELAY)
        
        # Progress report every 100 items
        if (i + 1) % 100 == 0:
            print(f'  TMDB progress: {i+1}/{total} (fetched: {fetched_count}, cached: {cached_count}, failed: {failed_count})')
    
    # Save updated cache
    save_release_date_cache(repo_root, cache)
    print(f'  TMDB enrichment done: {fetched_count} fetched, {cached_count} cached, {failed_count} failed')
    
    return items


# ═══════════════════════════════════════════════════════════════════════════════
# Sorting
# ═══════════════════════════════════════════════════════════════════════════════

def sort_items(items: list[dict], priorities: dict[str, int]) -> list[dict]:
    """Sort: year DESC → release_date DESC → batch priority ASC → id DESC.
    
    Within each year group, items are sorted by exact release date (most recent first).
    Within same date, batch priority determines order (latest batch first).
    """
    def sort_key(item: dict) -> tuple:
        year = safe_int(item.get('year') or item.get('release_year') or 0)
        
        # Parse release_date for sub-year ordering
        # Convert "2026-05-15" to sortable int 20260515
        release_date = item.get('release_date') or ''
        date_sortable = 0
        if release_date and len(release_date) >= 10:
            try:
                date_sortable = int(release_date[:10].replace('-', ''))
            except ValueError:
                pass
        
        item_id = safe_int(item.get('id') or 0)
        media_type = item.get('type') or item.get('media_type', 'movie')
        key = f"{item.get('id')}-{media_type}"
        priority = priorities.get(key, 999999)
        
        return (-year, -date_sortable, priority, -item_id)

    return sorted(items, key=sort_key)


# ═══════════════════════════════════════════════════════════════════════════════
# Category Matching
# ═══════════════════════════════════════════════════════════════════════════════

def has_category_metadata(item: dict) -> bool:
    """Check if item has enough metadata for category placement.
    
    Items without origin_country AND original_language go to Explore only.
    """
    has_orig_lang = bool((item.get('original_language') or '').strip())
    has_country = bool(item.get('country') or item.get('origin_country'))
    return has_orig_lang or has_country


def matches_category(item: dict, cat_config: dict) -> bool:
    """Check if item belongs to a category.
    
    ONLY uses origin_country and original_language.
    NEVER uses the 'language' field (that's dubbing/audio availability for display only).
    """
    countries = [c.upper() for c in cat_config.get('countries', [])]
    languages = [l.lower() for l in cat_config.get('languages', [])]
    genre_names = [g.lower() for g in cat_config.get('genres', [])]

    # Item fields
    item_countries = item.get('country') or item.get('origin_country') or []
    if isinstance(item_countries, str):
        item_countries = [item_countries]
    item_countries = [c.upper() for c in item_countries]

    item_orig_lang = (item.get('original_language') or '').lower().strip()

    # ✅ Country match (origin_country only)
    if countries and any(c in countries for c in item_countries):
        return True

    # ✅ Original language match ONLY (NOT the dubbing 'language' field)
    if languages and item_orig_lang in languages:
        return True

    # ❌ REMOVED: language list match — was matching dubbing language
    # This caused 99% of items to match bollywood because nearly every item
    # has language: ["Hindi"] for Hindi dubbing/audio availability

    # Genre match (for anime: also require Japanese original_language)
    if genre_names:
        item_genres = item.get('genres') or []
        if isinstance(item_genres, str):
            item_genres = [item_genres]
        item_genres_lower = [g.lower().strip() for g in item_genres]

        if any(g in genre_names for g in item_genres_lower):
            if 'japanese' in languages or 'ja' in languages:
                return item_orig_lang in ('ja', 'japanese')
            return True

    return False


# ═══════════════════════════════════════════════════════════════════════════════
# Pagination & Output
# ═══════════════════════════════════════════════════════════════════════════════

def paginate(items: list[dict], page_size: int) -> list[list[dict]]:
    """Split items into pages."""
    if not items:
        return [[]]
    pages = []
    for i in range(0, len(items), page_size):
        pages.append(items[i:i + page_size])
    return pages


def write_json(path: str, data: Any):
    """Write JSON file, creating dirs as needed."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))


# ═══════════════════════════════════════════════════════════════════════════════
# Main Catalog Generation
# ═══════════════════════════════════════════════════════════════════════════════

def generate_catalog(repo_root: str, output_dir: str, page_size: int = PAGE_SIZE):
    """Generate the full paginated catalog."""

    # ─── Step 1: Load items from both sources ─────────────────────────────
    print('Loading items...')
    
    # Source 1: streaming_links/ folder (source of truth)
    streaming_items = load_streaming_links(repo_root)
    print(f'  streaming_links/: {len(streaming_items)} items')
    
    # Source 2: index.json (secondary/fallback)
    index_items = load_index_json(repo_root)
    print(f'  index.json: {len(index_items)} items')
    
    # Merge: streaming_links overrides index.json
    items = merge_items(streaming_items, index_items)
    print(f'  Merged: {len(items)} unique items')

    if not items:
        print('ERROR: No items found!', file=sys.stderr)
        sys.exit(1)

    # Filter out non-numeric IDs (can't be used as TMDB IDs)
    valid_items = [item for item in items if safe_int(item.get('id')) > 0]
    print(f'  {len(valid_items)} items with valid numeric IDs (skipped {len(items) - len(valid_items)})')
    items = valid_items

    # ─── Step 2: Load posting record ──────────────────────────────────────
    print('Loading posting record...')
    priorities = load_posting_record(repo_root)
    print(f'  {len(priorities)} batch-prioritized items')

    # ─── Step 3: Fetch release dates from TMDB ────────────────────────────
    print('Enriching with TMDB release dates...')
    items = enrich_with_release_dates(items, repo_root)
    
    # Count items with/without release dates
    with_date = sum(1 for item in items if item.get('release_date'))
    without_date = len(items) - with_date
    print(f'  {with_date} items with release_date, {without_date} without')

    # ─── Step 4: Sort ─────────────────────────────────────────────────────
    print('Sorting (year DESC -> release_date DESC -> batch priority -> id DESC)...')
    sorted_items = sort_items(items, priorities)

    # ─── Step 5: Paginate all categories ──────────────────────────────────
    page_counts: dict[str, int] = {}

    # Global (all) — includes ALL items regardless of metadata
    print('Generating all/ pages...')
    all_pages = paginate(sorted_items, page_size)
    page_counts['all'] = len(all_pages)
    for i, page_items in enumerate(all_pages):
        write_json(os.path.join(output_dir, 'all', f'page_{i+1}.json'), {
            'page': i + 1,
            'total_pages': len(all_pages),
            'total_items': len(sorted_items),
            'items': page_items,
        })
    print(f'  all: {len(all_pages)} pages ({len(sorted_items)} items)')

    # Category pages — only items WITH category metadata
    for cat_name, cat_config in CATEGORIES.items():
        cat_items = [
            item for item in sorted_items
            if has_category_metadata(item) and matches_category(item, cat_config)
        ]
        cat_pages = paginate(cat_items, page_size)
        page_counts[cat_name] = len(cat_pages)
        for i, page_items in enumerate(cat_pages):
            write_json(os.path.join(output_dir, cat_name, f'page_{i+1}.json'), {
                'page': i + 1,
                'total_pages': len(cat_pages),
                'total_items': len(cat_items),
                'items': page_items,
            })
        print(f'  {cat_name}: {len(cat_pages)} pages ({len(cat_items)} items)')

    # ─── Step 6: meta.json ────────────────────────────────────────────────
    version = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    meta = {
        'version': version,
        'total_items': len(sorted_items),
        'page_size': page_size,
        'pages': page_counts,
    }
    write_json(os.path.join(output_dir, 'meta.json'), meta)
    print(f'Generated meta.json (version: {version})')

    # ─── Step 7: search_index.json ────────────────────────────────────────
    search_index = []
    for item in sorted_items:
        lang = item.get('language') or []
        if isinstance(lang, str):
            lang = [lang]
        if not lang and item.get('original_language'):
            lang = [item['original_language']]
        search_index.append({
            'i': safe_int(item.get('id')),
            't': item.get('title', ''),
            'm': item.get('type') or item.get('media_type', 'movie'),
            'l': lang,
        })
    write_json(os.path.join(output_dir, 'search_index.json'), search_index)
    print(f'Generated search_index.json ({len(search_index)} entries)')

    # ─── Step 8: home/sections.json ───────────────────────────────────────
    print('Generating home sections...')
    top5 = load_top_content(repo_root, 'Top 5')
    top10 = load_top_content(repo_root, 'Top 10')

    # Carousel: first 5 sorted items (or top5 if available)
    carousel = (top5 if top5 else sorted_items)[:5]

    sections = []
    for sec in HOME_SECTIONS:
        title = sec['title']
        filt = sec['filter']
        limit = sec.get('limit', 20)
        is_ranked = sec.get('is_ranked', False)

        if filt == 'trending':
            sec_items = sorted_items[:limit]
        elif filt == 'top10':
            sec_items = (top10 if top10 else sorted_items)[:limit]
        elif filt == 'top_rated':
            rated = sorted(sorted_items, key=lambda x: -(x.get('vote_average') or 0))
            sec_items = rated[:limit]
        elif filt in CATEGORIES:
            cat_items = [
                item for item in sorted_items
                if has_category_metadata(item) and matches_category(item, CATEGORIES[filt])
            ]
            sec_items = cat_items[:limit]
        else:
            sec_items = sorted_items[:limit]

        if sec_items:
            sections.append({
                'title': title,
                'items': sec_items,
                'is_ranked': is_ranked,
            })

    write_json(os.path.join(output_dir, 'home', 'sections.json'), {
        'carousel': carousel,
        'sections': sections,
    })
    print(f'Generated home/sections.json ({len(sections)} sections, {len(carousel)} carousel)')

    total_pages = sum(page_counts.values())
    print(f'\nDONE! Catalog generated: {len(sorted_items)} items, {total_pages} total pages')
    
    # Print category summary
    print('\n── Category Summary ──')
    for cat, count in page_counts.items():
        total = count * page_size  # approximate
        # Get actual count
        if cat == 'all':
            actual = len(sorted_items)
        else:
            actual = len([
                item for item in sorted_items
                if has_category_metadata(item) and matches_category(item, CATEGORIES.get(cat, {}))
            ]) if cat in CATEGORIES else 0
        print(f'  {cat:15s}: {actual:5d} items ({count} pages)')


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Generate paginated catalog for DanieWatch')
    parser.add_argument('--repo-root', default='.', help='Root of the database repository')
    parser.add_argument('--output-dir', default='./catalog', help='Output directory')
    parser.add_argument('--page-size', type=int, default=PAGE_SIZE, help='Items per page')
    args = parser.parse_args()
    generate_catalog(args.repo_root, args.output_dir, args.page_size)
