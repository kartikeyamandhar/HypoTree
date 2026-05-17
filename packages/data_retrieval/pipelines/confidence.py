"""Confidence scoring for retrieved data points."""
from __future__ import annotations

from packages.shared.types import ConfidenceLevel


def score_source_confidence(source: str, source_url: str = "") -> ConfidenceLevel:
    """Rate confidence based on source authority."""
    high_authority = [
        "sec.gov", "sec edgar", "10-k", "10-q", "annual report",
        "world bank", "imf", "federal reserve", "census.gov",
        "bls.gov", "treasury.gov",
    ]
    medium_authority = [
        "yahoo finance", "bloomberg", "reuters", "wsj",
        "financial times", "statista", "euromonitor",
        "company investor relations", "earnings call",
    ]

    source_lower = (source + " " + source_url).lower()

    for term in high_authority:
        if term in source_lower:
            return ConfidenceLevel.HIGH

    for term in medium_authority:
        if term in source_lower:
            return ConfidenceLevel.MEDIUM

    return ConfidenceLevel.LOW
