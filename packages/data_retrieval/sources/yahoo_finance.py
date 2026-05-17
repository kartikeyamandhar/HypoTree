"""Yahoo Finance data retrieval — free, no API key required."""
from __future__ import annotations

import logging
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

YAHOO_BASE = "https://query1.finance.yahoo.com/v8/finance"


def get_quote(ticker: str) -> Optional[dict]:
    """Fetch current quote data for a ticker."""
    try:
        url = f"{YAHOO_BASE}/chart/{ticker}?range=1d&interval=1d"
        headers = {"User-Agent": "Mozilla/5.0"}
        resp = httpx.get(url, headers=headers, timeout=10)
        if resp.status_code != 200:
            logger.warning("Yahoo Finance returned %d for %s", resp.status_code, ticker)
            return None
        data = resp.json()
        result = data.get("chart", {}).get("result", [])
        if not result:
            return None
        meta = result[0].get("meta", {})
        return {
            "ticker": ticker,
            "price": meta.get("regularMarketPrice"),
            "previous_close": meta.get("chartPreviousClose"),
            "currency": meta.get("currency"),
            "exchange": meta.get("exchangeName"),
            "market_cap": None,
        }
    except Exception as e:
        logger.warning("Yahoo Finance error for %s: %s", ticker, str(e))
        return None


def get_financials_summary(ticker: str) -> Optional[dict]:
    """Fetch key financial metrics using the quoteSummary endpoint."""
    try:
        url = f"https://query1.finance.yahoo.com/v10/finance/quoteSummary/{ticker}"
        params = {"modules": "financialData,defaultKeyStatistics,incomeStatementHistory"}
        headers = {"User-Agent": "Mozilla/5.0"}
        resp = httpx.get(url, headers=headers, params=params, timeout=10)
        if resp.status_code != 200:
            logger.warning("Yahoo quoteSummary returned %d for %s", resp.status_code, ticker)
            return None
        data = resp.json()
        result = data.get("quoteSummary", {}).get("result", [])
        if not result:
            return None

        fin = result[0].get("financialData", {})
        stats = result[0].get("defaultKeyStatistics", {})

        return {
            "ticker": ticker,
            "revenue": _extract_raw(fin.get("totalRevenue")),
            "ebitda": _extract_raw(fin.get("ebitda")),
            "gross_margin": _extract_raw(fin.get("grossMargins")),
            "operating_margin": _extract_raw(fin.get("operatingMargins")),
            "profit_margin": _extract_raw(fin.get("profitMargins")),
            "market_cap": _extract_raw(stats.get("marketCap")),
            "enterprise_value": _extract_raw(stats.get("enterpriseValue")),
            "pe_ratio": _extract_raw(stats.get("trailingPE")),
            "ev_ebitda": _extract_raw(stats.get("enterpriseToEbitda")),
            "revenue_growth": _extract_raw(fin.get("revenueGrowth")),
        }
    except Exception as e:
        logger.warning("Yahoo financials error for %s: %s", ticker, str(e))
        return None


def _extract_raw(obj) -> Optional[float]:
    if isinstance(obj, dict):
        return obj.get("raw")
    return obj
