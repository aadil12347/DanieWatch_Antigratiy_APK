"""
Upload index.json to Algolia with all metadata fields.
Reads from index.json (the app's master data) and uploads to Algolia
with: poster, genres, originalLanguage, country, year, imdb_id, languages.
"""
import json
import urllib.request
import urllib.error
import sys
import os

APP_ID = "EFW385VZRX"
API_KEY = "2c8fcfc8529ed03dcbd69074404e2e88"
INDEX_NAME = "daniewatch_catalog"

def main():
    index_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "index.json")
    if not os.path.exists(index_path):
        print(f"ERROR: index.json not found at {index_path}")
        sys.exit(1)

    with open(index_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    posts = data.get('posts', [])
    print(f"Loaded {len(posts)} items from index.json")

    # First, clear the index to remove stale records
    print("Clearing existing Algolia index...")
    clear_url = f"https://{APP_ID}.algolia.net/1/indexes/{INDEX_NAME}/clear"
    clear_req = urllib.request.Request(clear_url, data=b'', headers={
        "X-Algolia-Application-Id": APP_ID,
        "X-Algolia-API-Key": API_KEY,
        "Content-Type": "application/json"
    }, method='POST')
    try:
        with urllib.request.urlopen(clear_req) as resp:
            print(f"  Index cleared: {resp.read().decode()}")
    except urllib.error.URLError as e:
        print(f"  WARNING: Could not clear index: {e}")

    # Build Algolia records
    batch_url = f"https://{APP_ID}.algolia.net/1/indexes/{INDEX_NAME}/batch"
    headers = {
        "X-Algolia-Application-Id": APP_ID,
        "X-Algolia-API-Key": API_KEY,
        "Content-Type": "application/json"
    }

    requests_list = []
    skipped = 0

    for item in posts:
        item_id = item.get('id', '')
        if not item_id:
            skipped += 1
            continue

        media_type = item.get('type', 'movie')
        obj_id = f"{item_id}-{media_type}"

        # Poster URL — use directly from index.json (already resolved)
        poster_url = item.get('poster', '') or ''
        # Skip .avif posters (not renderable in Flutter)
        if poster_url.lower().endswith('.avif'):
            poster_url = ''

        # Languages (dubbing/audio)
        lang = item.get('language', [])
        if isinstance(lang, str):
            lang = [lang]

        # Original language (ISO code like 'en', 'hi', 'ja')
        original_language = (item.get('original_language') or '').lower().strip()

        # Genres
        genres = item.get('genres', [])
        if isinstance(genres, str):
            genres = [genres]

        # Country
        country = item.get('country', [])
        if isinstance(country, str):
            country = [country]

        # Year
        year_str = item.get('year', '0')
        try:
            year = int(year_str)
        except (ValueError, TypeError):
            year = 0

        # IMDB ID
        imdb_id = item.get('imdb_id', '') or ''

        record = {
            "objectID": obj_id,
            "itemId": item_id,
            "mediaType": media_type,
            "title": item.get('title', ''),
            "posterUrl": poster_url,
            "languages": lang,
            "originalLanguage": original_language,
            "genres": genres,
            "releaseYear": year,
            "originCountry": country,
            "imdbId": imdb_id,
        }

        requests_list.append({
            "action": "updateObject",
            "body": record
        })

    print(f"Built {len(requests_list)} records (skipped {skipped})")

    # Configure index settings (facets, searchable attributes)
    print("\nConfiguring Algolia index settings...")
    settings_url = f"https://{APP_ID}.algolia.net/1/indexes/{INDEX_NAME}/settings"
    settings = {
        "searchableAttributes": [
            "title",
            "genres",
            "originalLanguage",
            "languages"
        ],
        "attributesForFaceting": [
            "filterOnly(originalLanguage)",
            "filterOnly(genres)",
            "filterOnly(releaseYear)",
            "filterOnly(originCountry)",
            "filterOnly(mediaType)",
            "filterOnly(languages)"
        ],
        "customRanking": [
            "desc(releaseYear)"
        ],
        "analytics": True
    }
    settings_body = json.dumps(settings).encode('utf-8')
    settings_req = urllib.request.Request(settings_url, data=settings_body, headers=headers, method='PUT')
    try:
        with urllib.request.urlopen(settings_req) as resp:
            print(f"  Settings configured: {resp.read().decode()}")
    except urllib.error.URLError as e:
        print(f"  ERROR configuring settings: {e}")

    # Upload in batches of 1000
    chunk_size = 1000
    total = len(requests_list)
    print(f"\nUploading {total} records in chunks of {chunk_size}...")

    for i in range(0, total, chunk_size):
        chunk = requests_list[i:i + chunk_size]
        body = json.dumps({"requests": chunk}).encode('utf-8')
        req = urllib.request.Request(batch_url, data=body, headers=headers, method='POST')
        try:
            with urllib.request.urlopen(req) as response:
                resp_data = json.loads(response.read().decode())
                print(f"  Batch {i+1}-{min(i+chunk_size, total)}: OK ({len(resp_data.get('objectIDs', []))} objects)")
        except urllib.error.URLError as e:
            print(f"  ERROR batch {i+1}-{min(i+chunk_size, total)}: {e}")
            if hasattr(e, 'read'):
                print(f"    {e.read().decode('utf-8')}")

    print(f"\n✅ Successfully uploaded {total} records to Algolia!")
    print(f"   Index: {INDEX_NAME}")
    print(f"   Fields: itemId, mediaType, title, posterUrl, languages, originalLanguage, genres, releaseYear, originCountry, imdbId")


if __name__ == '__main__':
    main()
