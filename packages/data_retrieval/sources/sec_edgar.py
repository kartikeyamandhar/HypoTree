"""SEC EDGAR data retrieval — free, no API key required."""
from __future__ import annotations

import logging
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

EDGAR_BASE = "https://efts.sec.gov/LATEST"
EDGAR_COMPANY = "https://data.sec.gov/submissions"


def search_company(company_name: str) -> Optional[dict]:
    """Search for a company CIK and basic info."""
    try:
        url = f"{EDGAR_BASE}/search-index?q={company_name}&dateRange=custom&startdt=2024-01-01&forms=10-K"
        headers = {"User-Agent": "HypoTree research@hypotree.dev", "Accept": "application/json"}
        resp = httpx.get(url, headers=headers, timeout=10)
        if resp.status_code != 200:
            return None
        data = resp.json()
        hits = data.get("hits", {}).get("hits", [])
        if not hits:
            return None
        first = hits[0].get("_source", {})
        return {
            "company_name": first.get("display_names", [company_name])[0] if first.get("display_names") else company_name,
            "cik": first.get("entity_id"),
            "form_type": first.get("form_type"),
            "filing_date": first.get("file_date"),
            "file_url": first.get("file_num"),
        }
    except Exception as e:
        logger.warning("SEC EDGAR search error for %s: %s", company_name, str(e))
        return None


def get_company_filings(cik: str, form_type: str = "10-K", count: int = 3) -> list[dict]:
    """Get recent filings for a company by CIK."""
    try:
        cik_padded = cik.zfill(10)
        url = f"{EDGAR_COMPANY}/CIK{cik_padded}.json"
        headers = {"User-Agent": "HypoTree research@hypotree.dev"}
        resp = httpx.get(url, headers=headers, timeout=10)
        if resp.status_code != 200:
            return []
        data = resp.json()
        recent = data.get("filings", {}).get("recent", {})
        forms = recent.get("form", [])
        dates = recent.get("filingDate", [])
        accessions = recent.get("accessionNumber", [])

        results = []
        for i, form in enumerate(forms):
            if form == form_type and len(results) < count:
                results.append({
                    "form_type": form,
                    "filing_date": dates[i] if i < len(dates) else None,
                    "accession": accessions[i] if i < len(accessions) else None,
                    "url": f"https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK={cik}&type={form_type}",
                })
        return results
    except Exception as e:
        logger.warning("SEC EDGAR filings error for %s: %s", cik, str(e))
        return []
