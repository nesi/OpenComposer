#!/usr/bin/env python3
"""
Downloads icons for OpenComposer apps using the Wikipedia REST API.
Run from the project root: python download_icons.py

Skips apps that already have an icon: entry in their manifest.yml.

Parallelism is two-level:
  - Outer: MAX_WORKERS apps processed concurrently.
  - Inner: each app fires all three Wikipedia strategies (direct name,
           disambiguated name, full-text search) concurrently and returns
           as soon as the first hit comes back.

Hit rate: ~30-50%. Specialised HPC tools without a Wikipedia page
will keep the default placeholder image shown by OpenComposer.
"""
import json
import os
import re
import ssl
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

APPS_DIR    = os.path.join(os.path.dirname(__file__), "apps")
MAX_WORKERS = 20   # outer: apps in flight at once

_CTX     = ssl.create_default_context()
_HEADERS = {"User-Agent": "NeSI-OpenComposer-IconBot/1.0 (https://github.com/nesi)"}


# ---------------------------------------------------------------------------
# Wikipedia helpers
# ---------------------------------------------------------------------------

def _get_json(url):
    req = urllib.request.Request(url, headers=_HEADERS)
    with urllib.request.urlopen(req, context=_CTX, timeout=10) as resp:
        return json.loads(resp.read().decode())


def _try_direct(name):
    """Direct Wikipedia page lookup by name. Returns thumbnail URL or None."""
    try:
        slug = urllib.parse.quote(name.replace(" ", "_"))
        data = _get_json(f"https://en.wikipedia.org/api/rest_v1/page/summary/{slug}")
        return data.get("thumbnail", {}).get("source")
    except Exception:
        return None


def _try_search(name):
    """Wikipedia full-text search → top result's page thumbnail. Returns URL or None."""
    try:
        params = urllib.parse.urlencode({
            "action":   "query",
            "list":     "search",
            "srsearch": name,
            "format":   "json",
            "srlimit":  1,
        })
        data = _get_json(f"https://en.wikipedia.org/w/api.php?{params}")
        hits = data.get("query", {}).get("search", [])
        if not hits:
            return None
        slug  = urllib.parse.quote(hits[0]["title"].replace(" ", "_"))
        data2 = _get_json(f"https://en.wikipedia.org/api/rest_v1/page/summary/{slug}")
        return data2.get("thumbnail", {}).get("source")
    except Exception:
        return None


def find_thumbnail_url(name):
    """
    Fire all three lookup strategies concurrently and return the first hit.

    Strategies run in parallel (not sequentially), so the wall-clock time is
    max(strategy times) rather than sum — typically one network round-trip.
    """
    # shutdown(wait=False) lets threads finish in the background if we return
    # early; their results are simply discarded.
    pool = ThreadPoolExecutor(max_workers=3)
    futures = [
        pool.submit(_try_direct, name),
        pool.submit(_try_direct, f"{name} (software)"),
        pool.submit(_try_search, name),
    ]
    pool.shutdown(wait=False)

    for f in as_completed(futures):
        url = f.result()
        if url:
            return url
    return None


def _url_ext(url):
    """Extract file extension from a URL (e.g. '.png', '.jpg', '.svg')."""
    path = url.split("?")[0]
    _, ext = os.path.splitext(path)
    return ext.lower() if ext else ".png"


def _download_bytes(url):
    req = urllib.request.Request(url, headers=_HEADERS)
    with urllib.request.urlopen(req, context=_CTX, timeout=20) as resp:
        return resp.read()


# ---------------------------------------------------------------------------
# Manifest helpers
# ---------------------------------------------------------------------------

def manifest_has_icon(path):
    with open(path) as f:
        return bool(re.search(r"^icon:", f.read(), re.MULTILINE))


def set_icon_in_manifest(path, icon_name):
    with open(path) as f:
        content = f.read()
    if re.search(r"^icon:", content, re.MULTILINE):
        content = re.sub(r"^icon:.*$", f"icon: {icon_name}", content, flags=re.MULTILINE)
    else:
        content = content.rstrip("\n") + f"\nicon: {icon_name}\n"
    with open(path, "w") as f:
        f.write(content)


# ---------------------------------------------------------------------------
# Per-app worker
# ---------------------------------------------------------------------------

def process_app(dir_name):
    """Download an icon for one app. Returns (dir_name, True/False)."""
    app_dir       = os.path.join(APPS_DIR, dir_name)
    manifest_path = os.path.join(app_dir, "manifest.yml")

    thumb_url = find_thumbnail_url(dir_name)
    if not thumb_url:
        return (dir_name, False)

    ext       = _url_ext(thumb_url)
    icon_name = f"icon{ext}"
    dest      = os.path.join(app_dir, icon_name)

    try:
        data = _download_bytes(thumb_url)
        with open(dest, "wb") as fh:
            fh.write(data)
        set_icon_in_manifest(manifest_path, icon_name)
        return (dir_name, True)
    except Exception:
        return (dir_name, False)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    all_dirs = sorted([
        d for d in os.listdir(APPS_DIR)
        if not d.startswith(".")
        and os.path.isdir(os.path.join(APPS_DIR, d))
    ])

    to_process = [
        d for d in all_dirs
        if os.path.exists(os.path.join(APPS_DIR, d, "manifest.yml"))
        and not manifest_has_icon(os.path.join(APPS_DIR, d, "manifest.yml"))
    ]

    already = len(all_dirs) - len(to_process)
    print(f"{len(to_process)} apps need icons  |  {already} already have one or no manifest")
    print(f"Running with {MAX_WORKERS} outer workers + 3 inner per app\n")

    found   = 0
    missing = []

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {pool.submit(process_app, d): d for d in to_process}
        for future in tqdm(as_completed(futures), total=len(futures),
                           desc="Fetching icons", unit="app"):
            name, ok = future.result()
            if ok:
                found += 1
            else:
                missing.append(name)

    print(f"\nDone.")
    print(f"  Downloaded : {found}")
    print(f"  Not found  : {len(missing)}")
    if missing:
        print(f"\nApps with no Wikipedia thumbnail ({len(missing)} total):")
        for m in sorted(missing):
            print(f"  {m}")


if __name__ == "__main__":
    main()
