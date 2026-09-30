# DanieWatch Cloudflare Worker Edge Scraper

This worker provides **<80ms edge cached responses** for VegaMovies and RogMovies content.

## Quick 1-Minute Free Deployment

1. Install Wrangler (if not already installed):
   ```bash
   npm install -g wrangler
   ```

2. Login to your free Cloudflare account:
   ```bash
   wrangler login
   ```

3. Deploy the worker:
   ```bash
   cd cloudflare_worker
   wrangler deploy
   ```

4. Once deployed, Cloudflare will print your worker URL:
   `https://daniewatch-edge-scraper.<your-subdomain>.workers.dev`

5. Add this URL to your app's `.dart_define.env`:
   ```env
   EDGE_WORKER_URL=https://daniewatch-edge-scraper.<your-subdomain>.workers.dev
   ```

## Endpoints Provided

- `GET /api/home`:
  - Returns Top 10 Indian Today (2026 releases, excluding reality shows).
  - Returns Top 10 Hindi Dub Today (Vega + Rog distinct).
  - Returns Featured Carousel items.
  - Automatically edge-cached for 10 minutes across Cloudflare's global CDN.

- `GET /api/category?name=korean&page=1`:
  - Returns category posts for Korean, Chinese, Anime, Action, Comedy, etc.
  - Edge-cached for 15 minutes.
