"""Public web fetch — no API key, direct HTTP requests."""
from __future__ import annotations

import logging
from typing import Optional

import httpx
from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)


def fetch_page_text(url: str, max_chars: int = 5000) -> Optional[str]:
    """Fetch a web page and extract text content."""
    try:
        headers = {"User-Agent": "Mozilla/5.0 (compatible; HypoTree/1.0)"}
        resp = httpx.get(url, headers=headers, timeout=15, follow_redirects=True)
        if resp.status_code != 200:
            return None
        soup = BeautifulSoup(resp.text, "html.parser")
        for tag in soup(["script", "style", "nav", "footer", "header"]):
            tag.decompose()
        text = soup.get_text(separator=" ", strip=True)
        return text[:max_chars]
    except Exception as e:
        logger.warning("Web fetch error for %s: %s", url, str(e))
        return None
