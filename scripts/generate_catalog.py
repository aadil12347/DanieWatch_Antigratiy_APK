#!/usr/bin/env python3
"""
Generate Paginated Catalog from index.json (DanieWatch format).

Reads index.json (with 'posts' key) + posting_record.json, sorts items
(year DESC → batch priority ASC → id DESC), splits into paginated files.

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
from datetime import datetime, timezone
from typing import Any

PAGE_SIZE = 50

# Category matching rules — language values are case-insensitive
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


def load_index_json(repo_root: str) -> list[dict]:
    """Load items from index.json."""
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


def sort_items(items: list[dict], priorities: dict[str, int]) -> list[dict]:
    """Sort: year DESC → batch priority ASC → id DESC."""
    def sort_key(item: dict) -> tuple:
        year = safe_int(item.get('year') or item.get('release_year') or 0)
        item_id = safe_int(item.get('id') or 0)
        media_type = item.get('type') or item.get('media_type', 'movie')
        key = f"{item.get('id')}-{media_type}"
        priority = priorities.get(key, 999999)
        return (-year, priority, -item_id)

    return sorted(items, key=sort_key)


def matches_category(item: dict, cat_config: dict) -> bool:
    """Check if item belongs to a category (case-insensitive)."""
    countries = [c.upper() for c in cat_config.get('countries', [])]
    languages = [l.lower() for l in cat_config.get('languages', [])]
    genre_names = [g.lower() for g in cat_config.get('genres', [])]

    # Item fields
    item_countries = item.get('country') or item.get('origin_country') or []
    if isinstance(item_countries, str):
        item_countries = [item_countries]
    item_countries = [c.upper() for c in item_countries]

    item_orig_lang = (item.get('original_language') or '').lower().strip()

    item_languages = item.get('language') or []
    if isinstance(item_languages, str):
        item_languages = [item_languages]
    item_languages_lower = [l.lower().strip() for l in item_languages]

    item_genres = item.get('genres') or []
    if isinstance(item_genres, str):
        item_genres = [item_genres]
    item_genres_lower = [g.lower().strip() for g in item_genres]

    # Country match
    if countries and any(c in countries for c in item_countries):
        return True

    # Original language match
    if languages and item_orig_lang in languages:
        return True

    # Language list match
    if languages and any(l in languages for l in item_languages_lower):
        return True

    # Genre match (for anime: also require Japanese language)
    if genre_names and any(g in genre_names for g in item_genres_lower):
        if 'japanese' in languages or 'ja' in languages:
            return item_orig_lang in ('ja', 'japanese') or any(l in ('ja', 'japanese') for l in item_languages_lower)
        return True

    return False


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


def generate_catalog(repo_root: str, output_dir: str, page_size: int = PAGE_SIZE):
    """Generate the full paginated catalog."""

    # Step 1: Load items (raw format — ManifestItem.fromJson handles field mapping)
    print('Loading items...')
    items = load_index_json(repo_root)
    print(f'  Loaded {len(items)} items')

    if not items:
        print('ERROR: No items found!', file=sys.stderr)
        sys.exit(1)

    # Filter out non-numeric IDs (can't be used as TMDB IDs)
    valid_items = [item for item in items if safe_int(item.get('id')) > 0]
    print(f'  {len(valid_items)} items with valid numeric IDs (skipped {len(items) - len(valid_items)})')
    items = valid_items

    # Step 2: Load posting record
    print('Loading posting record...')
    priorities = load_posting_record(repo_root)
    print(f'  {len(priorities)} batch-prioritized items')

    # Step 3: Sort
    print('Sorting...')
    sorted_items = sort_items(items, priorities)

    # Step 4: Paginate all categories
    page_counts: dict[str, int] = {}

    # Global (all)
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

    # Category pages
    for cat_name, cat_config in CATEGORIES.items():
        cat_items = [item for item in sorted_items if matches_category(item, cat_config)]
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

    # Step 5: meta.json
    version = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    meta = {
        'version': version,
        'total_items': len(sorted_items),
        'page_size': page_size,
        'pages': page_counts,
    }
    write_json(os.path.join(output_dir, 'meta.json'), meta)
    print(f'Generated meta.json (version: {version})')

    # Step 6: search_index.json (lightweight: id, title, type, language)
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

    # Step 7: home/sections.json
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
            cat_items = [item for item in sorted_items if matches_category(item, CATEGORIES[filt])]
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


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Generate paginated catalog for DanieWatch')
    parser.add_argument('--repo-root', default='.', help='Root of the database repository')
    parser.add_argument('--output-dir', default='./catalog', help='Output directory')
    parser.add_argument('--page-size', type=int, default=PAGE_SIZE, help='Items per page')
    args = parser.parse_args()
    generate_catalog(args.repo_root, args.output_dir, args.page_size)
