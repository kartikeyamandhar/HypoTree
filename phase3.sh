#!/bin/bash
set -e

# ============================================================
# HypoTree Phase 3 — Agentic Data Pre-Population
# Run from hypotree/ root
# Usage: bash phase3.sh
# ============================================================

echo "=== Phase 3: Agentic Data Pre-Population ==="

# ======================== SHARED TYPES — add data models ========================
cat > packages/shared/types.py << 'PYEOF'
"""Shared Pydantic models used across agents and API."""
from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class QuestionType(str, Enum):
    GROWTH_MARKET_ENTRY = "growth_market_entry"
    COST_OPTIMIZATION = "cost_optimization"
    MA_RATIONALE = "ma_rationale"
    PRICING_STRATEGY = "pricing_strategy"
    COMPETITIVE_RESPONSE = "competitive_response"
    DIGITAL_TRANSFORMATION = "digital_transformation"
    UNKNOWN = "unknown"


class Framework(str, Enum):
    THREE_CS_MARKET_ATTRACTIVENESS = "3cs_market_attractiveness"
    VALUE_CHAIN_DECOMPOSITION = "value_chain_decomposition"
    SYNERGY_TREE_STANDALONE = "synergy_tree_standalone"
    VALUE_BASED_PRICING = "value_based_pricing"
    GAME_THEORY_PORTERS = "game_theory_porters"
    CAPABILITY_MATURITY_ROI = "capability_maturity_roi"


QUESTION_TYPE_TO_FRAMEWORK: dict[QuestionType, Framework] = {
    QuestionType.GROWTH_MARKET_ENTRY: Framework.THREE_CS_MARKET_ATTRACTIVENESS,
    QuestionType.COST_OPTIMIZATION: Framework.VALUE_CHAIN_DECOMPOSITION,
    QuestionType.MA_RATIONALE: Framework.SYNERGY_TREE_STANDALONE,
    QuestionType.PRICING_STRATEGY: Framework.VALUE_BASED_PRICING,
    QuestionType.COMPETITIVE_RESPONSE: Framework.GAME_THEORY_PORTERS,
    QuestionType.DIGITAL_TRANSFORMATION: Framework.CAPABILITY_MATURITY_ROI,
}


class TestabilityClass(str, Enum):
    QUANTITATIVE = "quantitative"
    QUALITATIVE = "qualitative"
    ASSUMPTION = "assumption"
    ALREADY_ANSWERED = "already_answered"


class AnalysisType(str, Enum):
    REGRESSION = "regression"
    BENCHMARKING = "benchmarking"
    COHORT_ANALYSIS = "cohort_analysis"
    SCENARIO_MODELING = "scenario_modeling"
    BREAK_EVEN = "break_even"
    MARKET_SIZING = "market_sizing"
    COMPETITIVE_ANALYSIS = "competitive_analysis"
    FINANCIAL_MODELING = "financial_modeling"
    SURVEY_ANALYSIS = "survey_analysis"
    EXPERT_INTERVIEWS = "expert_interviews"
    CASE_STUDY = "case_study"
    DATA_ANALYSIS = "data_analysis"
    COST_ANALYSIS = "cost_analysis"
    SENSITIVITY_ANALYSIS = "sensitivity_analysis"


class ConfidenceLevel(str, Enum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class DataPoint(BaseModel):
    metric: str
    value: str
    source: str
    source_url: str = ""
    confidence: ConfidenceLevel = ConfidenceLevel.MEDIUM
    recency: str = ""
    notes: str = ""


class DataGap(BaseModel):
    description: str
    why_needed: str
    suggested_alternative: str = ""


class DataCard(BaseModel):
    hypothesis_id: str
    data_points: list[DataPoint] = Field(default_factory=list)
    gaps: list[DataGap] = Field(default_factory=list)
    summary: str = ""
    retrieval_status: str = "pending"


class TestabilityResult(BaseModel):
    classification: TestabilityClass
    confidence: float = 0.0
    rationale: str = ""
    impact_score: int = Field(default=3, ge=1, le=5)
    testability_score: int = Field(default=2, ge=1, le=3)
    data_availability_score: int = Field(default=2, ge=1, le=3)

    @property
    def priority_score(self) -> float:
        return self.impact_score * self.testability_score * self.data_availability_score


class AnalysisDesign(BaseModel):
    analysis_type: AnalysisType
    methodology: str = ""
    data_sources: list[str] = Field(default_factory=list)
    output_format: str = ""
    loe_hours: float = 0.0
    rationale: str = ""


class HypothesisNode(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4())[:8])
    statement: str
    parent_id: Optional[str] = None
    children: list[HypothesisNode] = Field(default_factory=list)
    depth: int = 0
    what_must_be_true: Optional[str] = None
    evidence_needed: Optional[str] = None
    is_leaf: bool = False
    testability: Optional[TestabilityResult] = None
    analysis: Optional[AnalysisDesign] = None
    data_card: Optional[DataCard] = None

    model_config = {"arbitrary_types_allowed": True}


class MECEValidationResult(BaseModel):
    is_valid: bool
    overlaps: list[str] = Field(default_factory=list)
    gaps: list[str] = Field(default_factory=list)
    suggestions: list[str] = Field(default_factory=list)


class ClassificationResult(BaseModel):
    question_type: QuestionType
    framework: Framework
    confidence: float
    rationale: str


class HypothesisTree(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    root: HypothesisNode
    classification: ClassificationResult
    industry: str
    company: str
    question: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    metadata: dict = Field(default_factory=dict)

    def get_all_nodes(self) -> list[HypothesisNode]:
        nodes: list[HypothesisNode] = []

        def _walk(node: HypothesisNode) -> None:
            nodes.append(node)
            for child in node.children:
                _walk(child)

        _walk(self.root)
        return nodes

    def get_leaf_nodes(self) -> list[HypothesisNode]:
        return [n for n in self.get_all_nodes() if n.is_leaf]


class ProjectCreate(BaseModel):
    industry: str
    company: str
    question: str


class ProjectResponse(BaseModel):
    id: str
    industry: str
    company: str
    question: str
    status: str
    tree: Optional[HypothesisTree] = None
    created_at: datetime
PYEOF

# ======================== DATA RETRIEVAL: YAHOO FINANCE ========================
cat > packages/data-retrieval/sources/yahoo_finance.py << 'PYEOF'
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
PYEOF

# ======================== DATA RETRIEVAL: SEC EDGAR ========================
cat > packages/data-retrieval/sources/sec_edgar.py << 'PYEOF'
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
PYEOF

# ======================== DATA RETRIEVAL: WEB FETCH ========================
cat > packages/data-retrieval/sources/web_search.py << 'PYEOF'
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
PYEOF

# ======================== DATA RETRIEVAL: CONFIDENCE SCORING ========================
cat > packages/data-retrieval/pipelines/confidence.py << 'PYEOF'
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
PYEOF

# ======================== DATA RETRIEVAL AGENT PROMPTS ========================
cat > packages/agents/data_retrieval/prompts.py << 'PYEOF'
DATA_RETRIEVAL_PROMPT = """You are a strategy consulting data analyst. Given a hypothesis and available financial data, create structured data points and identify gaps.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

Hypothesis: "{statement}"
Evidence needed: "{evidence_needed}"
Analysis type: {analysis_type}

Available data retrieved from public sources:
{available_data}

Based on the available data, create data points that are relevant to testing this hypothesis. Also identify critical data gaps.

For each data point, extract or derive a specific metric and value from the available data. Do NOT fabricate numbers. If the data doesn't contain a specific metric, list it as a gap instead.

Respond ONLY with valid JSON, no markdown fences:
{{
  "data_points": [
    {{
      "metric": "<specific metric name>",
      "value": "<actual value from the data, with units>",
      "source": "<source name>",
      "notes": "<brief context or caveat>"
    }}
  ],
  "gaps": [
    {{
      "description": "<what data is missing>",
      "why_needed": "<why this matters for the hypothesis>",
      "suggested_alternative": "<how to obtain this data>"
    }}
  ],
  "summary": "<2-3 sentence summary of data coverage for this hypothesis>"
}}"""
PYEOF

# ======================== DATA RETRIEVAL AGENT ========================
cat > packages/agents/data_retrieval/agent.py << 'PYEOF'
"""Data Retrieval Agent — fetches real data for testable hypotheses."""
from __future__ import annotations

import json
import logging
from typing import Optional

from packages.agents.base import BaseAgent
from packages.agents.data_retrieval.prompts import DATA_RETRIEVAL_PROMPT
from packages.data_retrieval.pipelines.confidence import score_source_confidence
from packages.data_retrieval.sources.sec_edgar import get_company_filings, search_company
from packages.data_retrieval.sources.yahoo_finance import get_financials_summary, get_quote
from packages.shared.types import (
    ConfidenceLevel,
    DataCard,
    DataGap,
    DataPoint,
    HypothesisNode,
    TestabilityClass,
)

logger = logging.getLogger(__name__)


class DataRetrievalAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a data analyst extracting structured data points from financial sources."

    def _gather_company_data(self, company: str, ticker: str = "") -> dict:
        """Gather all available data for a company from free sources."""
        gathered: dict = {"yahoo_quote": None, "yahoo_financials": None, "sec_info": None, "sec_filings": []}

        # Try Yahoo Finance
        if ticker:
            gathered["yahoo_quote"] = get_quote(ticker)
            gathered["yahoo_financials"] = get_financials_summary(ticker)

        # Try SEC EDGAR
        sec_info = search_company(company)
        gathered["sec_info"] = sec_info
        if sec_info and sec_info.get("cik"):
            gathered["sec_filings"] = get_company_filings(sec_info["cik"])

        return gathered

    def _format_available_data(self, data: dict) -> str:
        """Format gathered data into readable text for the LLM."""
        sections = []

        quote = data.get("yahoo_quote")
        if quote:
            sections.append(
                f"Yahoo Finance Quote:\n"
                f"  Price: {quote.get('price', 'N/A')} {quote.get('currency', '')}\n"
                f"  Exchange: {quote.get('exchange', 'N/A')}"
            )

        fin = data.get("yahoo_financials")
        if fin:
            lines = ["Yahoo Finance Financials:"]
            for key, label in [
                ("revenue", "Revenue"),
                ("ebitda", "EBITDA"),
                ("gross_margin", "Gross Margin"),
                ("operating_margin", "Operating Margin"),
                ("profit_margin", "Profit Margin"),
                ("market_cap", "Market Cap"),
                ("enterprise_value", "Enterprise Value"),
                ("pe_ratio", "P/E Ratio"),
                ("ev_ebitda", "EV/EBITDA"),
                ("revenue_growth", "Revenue Growth"),
            ]:
                val = fin.get(key)
                if val is not None:
                    if key in ("gross_margin", "operating_margin", "profit_margin", "revenue_growth"):
                        lines.append(f"  {label}: {val*100:.1f}%")
                    elif key in ("revenue", "ebitda", "market_cap", "enterprise_value"):
                        lines.append(f"  {label}: ${val/1e9:.2f}B")
                    else:
                        lines.append(f"  {label}: {val:.2f}")
            sections.append("\n".join(lines))

        sec = data.get("sec_info")
        if sec:
            sections.append(
                f"SEC EDGAR:\n"
                f"  Company: {sec.get('company_name', 'N/A')}\n"
                f"  CIK: {sec.get('cik', 'N/A')}\n"
                f"  Latest Filing: {sec.get('form_type', 'N/A')} ({sec.get('filing_date', 'N/A')})"
            )

        filings = data.get("sec_filings", [])
        if filings:
            filing_lines = ["Recent SEC Filings:"]
            for f in filings:
                filing_lines.append(f"  {f.get('form_type', 'N/A')} - {f.get('filing_date', 'N/A')}")
            sections.append("\n".join(filing_lines))

        if not sections:
            return "No public data was retrieved for this company."

        return "\n\n".join(sections)

    def _guess_tickers(self, company: str, industry: str) -> list[str]:
        """Attempt to guess ticker symbols from company name."""
        known = {
            "expedia": ["EXPE"],
            "makemytrip": ["MMYT"],
            "grab": ["GRAB"],
            "skyworks": ["SWKS"],
            "qorvo": ["QRVO"],
            "apple": ["AAPL"],
            "google": ["GOOGL"],
            "alphabet": ["GOOGL"],
            "amazon": ["AMZN"],
            "microsoft": ["MSFT"],
            "meta": ["META"],
            "nvidia": ["NVDA"],
            "tesla": ["TSLA"],
            "uber": ["UBER"],
            "airbnb": ["ABNB"],
            "booking": ["BKNG"],
            "tripadvisor": ["TRIP"],
        }
        company_lower = company.lower().strip()
        for key, tickers in known.items():
            if key in company_lower:
                return tickers
        return []

    def retrieve_for_hypothesis(
        self,
        node: HypothesisNode,
        industry: str,
        company: str,
        question: str,
        company_data: dict,
    ) -> DataCard:
        """Retrieve and structure data for a single hypothesis."""
        available_data_text = self._format_available_data(company_data)

        analysis_type = ""
        if node.analysis:
            analysis_type = node.analysis.analysis_type.value

        prompt = DATA_RETRIEVAL_PROMPT.format(
            industry=industry,
            company=company,
            question=question,
            statement=node.statement,
            evidence_needed=node.evidence_needed or "Not specified",
            analysis_type=analysis_type or "general",
            available_data=available_data_text,
        )

        try:
            raw = self.call_llm(prompt)
            data = json.loads(raw)
        except Exception as e:
            logger.warning("Data retrieval LLM failed for '%s': %s", node.statement[:50], str(e))
            return DataCard(
                hypothesis_id=node.id,
                gaps=[DataGap(
                    description="Data retrieval failed",
                    why_needed="Could not process available data for this hypothesis",
                    suggested_alternative="Manual research required",
                )],
                summary="Data retrieval encountered an error.",
                retrieval_status="error",
            )

        data_points = []
        for dp in data.get("data_points", []):
            source = dp.get("source", "Unknown")
            confidence = score_source_confidence(source)
            data_points.append(DataPoint(
                metric=dp.get("metric", ""),
                value=dp.get("value", ""),
                source=source,
                confidence=confidence,
                notes=dp.get("notes", ""),
            ))

        gaps = []
        for gap in data.get("gaps", []):
            gaps.append(DataGap(
                description=gap.get("description", ""),
                why_needed=gap.get("why_needed", ""),
                suggested_alternative=gap.get("suggested_alternative", ""),
            ))

        card = DataCard(
            hypothesis_id=node.id,
            data_points=data_points,
            gaps=gaps,
            summary=data.get("summary", ""),
            retrieval_status="complete" if data_points else "gaps_only",
        )

        logger.info(
            "Data card for '%s': %d data points, %d gaps",
            node.statement[:50], len(data_points), len(gaps),
        )
        return card

    def retrieve_for_tree(
        self,
        tree_root: HypothesisNode,
        industry: str,
        company: str,
        question: str,
    ) -> None:
        """Retrieve data for all eligible leaves in the tree."""
        # Gather company data once
        tickers = self._guess_tickers(company, industry)

        # Also try to find tickers for other companies mentioned in the question
        all_company_data: dict = {}

        primary_data = {}
        for ticker in tickers:
            ticker_data = self._gather_company_data(company, ticker)
            primary_data = self._merge_data(primary_data, ticker_data)

        if not primary_data.get("yahoo_quote") and not primary_data.get("yahoo_financials"):
            primary_data = self._gather_company_data(company)

        all_company_data[company.lower()] = primary_data

        # Extract other company names from question
        question_words = question.lower().split()
        for word in question_words:
            word_clean = word.strip("?.,!")
            if word_clean and word_clean not in company.lower().split():
                other_tickers = self._guess_tickers(word_clean, industry)
                if other_tickers:
                    other_data = {}
                    for t in other_tickers:
                        td = self._gather_company_data(word_clean, t)
                        other_data = self._merge_data(other_data, td)
                    all_company_data[word_clean] = other_data

        # Merge all company data into one view
        merged = {}
        for cname, cdata in all_company_data.items():
            merged = self._merge_data(merged, cdata)

        # Process eligible leaves
        leaves = self._get_eligible_leaves(tree_root)
        logger.info("Processing data retrieval for %d eligible leaves", len(leaves))

        for leaf in leaves:
            leaf.data_card = self.retrieve_for_hypothesis(
                node=leaf,
                industry=industry,
                company=company,
                question=question,
                company_data=merged,
            )

    def _get_eligible_leaves(self, node: HypothesisNode) -> list[HypothesisNode]:
        """Get leaves eligible for data retrieval (quantitative or already_answered)."""
        eligible = []

        def _walk(n: HypothesisNode) -> None:
            if n.is_leaf and n.testability:
                if n.testability.classification in (
                    TestabilityClass.QUANTITATIVE,
                    TestabilityClass.ALREADY_ANSWERED,
                ):
                    eligible.append(n)
                elif (
                    n.testability.classification == TestabilityClass.QUALITATIVE
                    and n.testability.data_availability_score >= 2
                ):
                    eligible.append(n)
            for child in n.children:
                _walk(child)

        _walk(node)
        return eligible

    @staticmethod
    def _merge_data(a: dict, b: dict) -> dict:
        merged = dict(a)
        for key, val in b.items():
            if val is not None and (key not in merged or merged[key] is None):
                merged[key] = val
            elif isinstance(val, list) and isinstance(merged.get(key), list):
                merged[key] = merged[key] + val
        return merged
PYEOF

# ======================== FIX IMPORT PATH for data_retrieval package ========================
# The package is packages/data-retrieval but Python needs underscores
# Create a symlink or just use the correct import path

cat > packages/data_retrieval/__init__.py << 'PYEOF'
# Re-export from data-retrieval (Python-friendly name)
PYEOF

mkdir -p packages/data_retrieval/sources
mkdir -p packages/data_retrieval/pipelines

cat > packages/data_retrieval/sources/__init__.py << 'PYEOF'
PYEOF

cat > packages/data_retrieval/pipelines/__init__.py << 'PYEOF'
PYEOF

# Copy source files to underscore path
cp packages/data-retrieval/sources/yahoo_finance.py packages/data_retrieval/sources/yahoo_finance.py
cp packages/data-retrieval/sources/sec_edgar.py packages/data_retrieval/sources/sec_edgar.py
cp packages/data-retrieval/sources/web_search.py packages/data_retrieval/sources/web_search.py
cp packages/data-retrieval/pipelines/confidence.py packages/data_retrieval/pipelines/confidence.py

# ======================== UPDATE ORCHESTRATOR — add Phase 3 ========================
cat > packages/agents/orchestrator/agent.py << 'PYEOF'
"""Orchestrator agent — routes tasks, classifies questions, manages tree generation."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.decomposer.agent import DecomposerAgent
from packages.agents.mece_validator.agent import MECEValidatorAgent
from packages.agents.testability_classifier.agent import TestabilityClassifierAgent
from packages.agents.analysis_designer.agent import AnalysisDesignerAgent
from packages.agents.data_retrieval.agent import DataRetrievalAgent
from packages.agents.orchestrator.prompts import CLASSIFICATION_PROMPT, ROOT_HYPOTHESIS_PROMPT
from packages.shared.constants import MECE_MAX_RETRIES, ORCHESTRATOR_MODEL, TARGET_TREE_DEPTH
from packages.shared.types import (
    ClassificationResult,
    Framework,
    HypothesisNode,
    HypothesisTree,
    QuestionType,
    TestabilityClass,
)

logger = logging.getLogger(__name__)


class OrchestratorAgent(BaseAgent):
    def __init__(self) -> None:
        super().__init__(model=ORCHESTRATOR_MODEL)
        self.decomposer = DecomposerAgent()
        self.mece_validator = MECEValidatorAgent()
        self.testability_classifier = TestabilityClassifierAgent()
        self.analysis_designer = AnalysisDesignerAgent()
        self.data_retrieval = DataRetrievalAgent()

    def get_system_prompt(self) -> str:
        return "You are a strategy consulting orchestrator."

    def classify_question(self, industry: str, company: str, question: str) -> ClassificationResult:
        prompt = CLASSIFICATION_PROMPT.format(industry=industry, company=company, question=question)
        raw = self.call_llm(prompt)
        data = json.loads(raw)
        return ClassificationResult(
            question_type=QuestionType(data["question_type"]),
            framework=Framework(data["framework"]),
            confidence=data["confidence"],
            rationale=data["rationale"],
        )

    def generate_root_and_branches(
        self, industry: str, company: str, question: str, classification: ClassificationResult
    ) -> HypothesisNode:
        prompt = ROOT_HYPOTHESIS_PROMPT.format(
            industry=industry,
            company=company,
            question=question,
            question_type=classification.question_type.value,
            framework=classification.framework.value,
        )
        raw = self.call_llm(prompt)
        data = json.loads(raw)

        root = HypothesisNode(
            statement=data["root"]["statement"],
            what_must_be_true=data["root"].get("what_must_be_true"),
            evidence_needed=data["root"].get("evidence_needed"),
            depth=0,
        )

        for child_data in data["children"]:
            child = HypothesisNode(
                statement=child_data["statement"],
                parent_id=root.id,
                what_must_be_true=child_data.get("what_must_be_true"),
                evidence_needed=child_data.get("evidence_needed"),
                depth=1,
            )
            root.children.append(child)

        return root

    def _decompose_with_validation(
        self, node: HypothesisNode, industry: str, company: str, question: str,
    ) -> list[HypothesisNode]:
        children = self.decomposer.decompose(
            parent=node, industry=industry, company=company, question=question,
        )
        best_children = children
        best_score = 999

        for attempt in range(MECE_MAX_RETRIES):
            validation = self.mece_validator.validate(parent=node, children=children)
            score = len(validation.overlaps) + len(validation.gaps)
            if score < best_score:
                best_score = score
                best_children = children
            if validation.is_valid:
                logger.info("MECE passed on attempt %d for '%s'", attempt + 1, node.statement[:50])
                return children
            logger.info("MECE attempt %d/%d for '%s': overlaps=%d gaps=%d",
                attempt + 1, MECE_MAX_RETRIES, node.statement[:50],
                len(validation.overlaps), len(validation.gaps))
            if attempt < MECE_MAX_RETRIES - 1:
                children = self.decomposer.decompose(
                    parent=node, industry=industry, company=company,
                    question=question, previous_issues=validation)
        logger.warning("MECE exhausted retries for '%s'. Accepting best (score=%d).",
            node.statement[:50], best_score)
        return best_children

    def _decompose_recursive(
        self, node: HypothesisNode, industry: str, company: str, question: str, target_depth: int,
    ) -> None:
        if node.depth >= target_depth:
            node.is_leaf = True
            return
        if not node.children:
            children = self._decompose_with_validation(node, industry, company, question)
            for child in children:
                child.parent_id = node.id
                child.depth = node.depth + 1
                node.children.append(child)
        for child in node.children:
            self._decompose_recursive(child, industry, company, question, target_depth)

    def _classify_and_design(
        self, node: HypothesisNode, industry: str, company: str, question: str,
    ) -> None:
        if not node.is_leaf:
            for child in node.children:
                self._classify_and_design(child, industry, company, question)
            return
        testability = self.testability_classifier.classify(
            node=node, industry=industry, company=company, question=question)
        node.testability = testability
        if testability.classification != TestabilityClass.ASSUMPTION or testability.impact_score >= 4:
            analysis = self.analysis_designer.design(
                node=node, testability=testability, industry=industry, company=company, question=question)
            node.analysis = analysis

    def generate_tree(self, industry: str, company: str, question: str) -> HypothesisTree:
        logger.info("Starting tree generation: %s / %s / %s", industry, company, question)

        # Phase 1
        classification = self.classify_question(industry, company, question)
        logger.info("Classification: %s (%.2f)", classification.question_type, classification.confidence)
        root = self.generate_root_and_branches(industry, company, question, classification)
        logger.info("Root generated with %d first-level branches", len(root.children))
        self._decompose_recursive(root, industry, company, question, TARGET_TREE_DEPTH)
        all_nodes = self._collect_all(root)
        leaf_count = len([n for n in all_nodes if n.is_leaf])
        logger.info("Decomposition complete: %d nodes, %d leaves", len(all_nodes), leaf_count)

        # Phase 2
        logger.info("Starting testability classification and analysis design...")
        self._classify_and_design(root, industry, company, question)
        classified = [n for n in all_nodes if n.testability is not None]
        logger.info("Phase 2 complete: %d leaves classified", len(classified))

        # Phase 3
        logger.info("Starting data pre-population...")
        self.data_retrieval.retrieve_for_tree(root, industry, company, question)
        data_cards = [n for n in all_nodes if n.data_card is not None]
        logger.info("Phase 3 complete: %d leaves with data cards", len(data_cards))

        return HypothesisTree(
            root=root, classification=classification,
            industry=industry, company=company, question=question,
        )

    @staticmethod
    def _collect_all(node: HypothesisNode) -> list[HypothesisNode]:
        result = [node]
        for child in node.children:
            result.extend(OrchestratorAgent._collect_all(child))
        return result
PYEOF

# ======================== FRONTEND TYPES — add data card types ========================
cat > apps/web/src/types/hypothesis.ts << 'TSEOF'
export type QuestionType =
  | 'growth_market_entry'
  | 'cost_optimization'
  | 'ma_rationale'
  | 'pricing_strategy'
  | 'competitive_response'
  | 'digital_transformation'
  | 'unknown';

export type TestabilityClass =
  | 'quantitative'
  | 'qualitative'
  | 'assumption'
  | 'already_answered';

export type AnalysisType =
  | 'regression'
  | 'benchmarking'
  | 'cohort_analysis'
  | 'scenario_modeling'
  | 'break_even'
  | 'market_sizing'
  | 'competitive_analysis'
  | 'financial_modeling'
  | 'survey_analysis'
  | 'expert_interviews'
  | 'case_study'
  | 'data_analysis'
  | 'cost_analysis'
  | 'sensitivity_analysis';

export type ConfidenceLevel = 'high' | 'medium' | 'low';

export interface DataPoint {
  metric: string;
  value: string;
  source: string;
  source_url: string;
  confidence: ConfidenceLevel;
  recency: string;
  notes: string;
}

export interface DataGap {
  description: string;
  why_needed: string;
  suggested_alternative: string;
}

export interface DataCard {
  hypothesis_id: string;
  data_points: DataPoint[];
  gaps: DataGap[];
  summary: string;
  retrieval_status: string;
}

export interface TestabilityResult {
  classification: TestabilityClass;
  confidence: number;
  rationale: string;
  impact_score: number;
  testability_score: number;
  data_availability_score: number;
  priority_score?: number;
}

export interface AnalysisDesign {
  analysis_type: AnalysisType;
  methodology: string;
  data_sources: string[];
  output_format: string;
  loe_hours: number;
  rationale: string;
}

export interface HypothesisNode {
  id: string;
  statement: string;
  parent_id: string | null;
  children: HypothesisNode[];
  depth: number;
  what_must_be_true: string | null;
  evidence_needed: string | null;
  is_leaf: boolean;
  testability: TestabilityResult | null;
  analysis: AnalysisDesign | null;
  data_card: DataCard | null;
}

export interface ClassificationResult {
  question_type: QuestionType;
  framework: string;
  confidence: number;
  rationale: string;
}

export interface HypothesisTree {
  id: string;
  root: HypothesisNode;
  classification: ClassificationResult;
  industry: string;
  company: string;
  question: string;
  created_at: string;
  metadata: Record<string, unknown>;
}
TSEOF

# ======================== CONFIDENCE BADGE COMPONENT ========================
cat > apps/web/src/components/data-cards/ConfidenceBadge.tsx << 'TSEOF'
import type { ConfidenceLevel } from '@/types/hypothesis';
import { cn } from '@/lib/utils';

const COLORS: Record<ConfidenceLevel, { bg: string; text: string }> = {
  high: { bg: 'bg-green-100', text: 'text-green-700' },
  medium: { bg: 'bg-yellow-100', text: 'text-yellow-700' },
  low: { bg: 'bg-red-100', text: 'text-red-700' },
};

interface Props {
  level: ConfidenceLevel;
  className?: string;
}

export function ConfidenceBadge({ level, className }: Props) {
  const color = COLORS[level];
  return (
    <span className={cn('text-xs px-1.5 py-0.5 rounded font-medium capitalize', color.bg, color.text, className)}>
      {level}
    </span>
  );
}
TSEOF

# ======================== GAP FLAG COMPONENT ========================
cat > apps/web/src/components/data-cards/GapFlag.tsx << 'TSEOF'
import type { DataGap } from '@/types/hypothesis';

interface Props {
  gap: DataGap;
}

export function GapFlag({ gap }: Props) {
  return (
    <div className="border border-amber-200 bg-amber-50 rounded-lg p-2.5 text-sm">
      <div className="flex items-start gap-2">
        <span className="text-amber-500 mt-0.5 flex-shrink-0">&#9888;</span>
        <div>
          <p className="font-medium text-amber-800">{gap.description}</p>
          <p className="text-amber-600 text-xs mt-0.5">{gap.why_needed}</p>
          {gap.suggested_alternative && (
            <p className="text-amber-500 text-xs mt-0.5 italic">Alt: {gap.suggested_alternative}</p>
          )}
        </div>
      </div>
    </div>
  );
}
TSEOF

# ======================== DATA CARD COMPONENT ========================
cat > apps/web/src/components/data-cards/DataCard.tsx << 'TSEOF'
import type { DataCard as DataCardType } from '@/types/hypothesis';
import { ConfidenceBadge } from './ConfidenceBadge';
import { GapFlag } from './GapFlag';

interface Props {
  card: DataCardType;
}

export function DataCardView({ card }: Props) {
  const statusColor = card.retrieval_status === 'complete'
    ? 'text-green-600'
    : card.retrieval_status === 'gaps_only'
    ? 'text-amber-600'
    : 'text-red-600';

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h4 className="text-sm font-medium text-slate-500">Data Card</h4>
        <span className={`text-xs font-medium capitalize ${statusColor}`}>
          {card.retrieval_status.replace(/_/g, ' ')}
        </span>
      </div>

      {card.summary && (
        <p className="text-sm text-slate-600 bg-slate-50 p-2 rounded">{card.summary}</p>
      )}

      {card.data_points.length > 0 && (
        <div className="space-y-2">
          <h5 className="text-xs font-medium text-slate-400 uppercase tracking-wide">Data Points</h5>
          {card.data_points.map((dp, i) => (
            <div key={i} className="bg-white border border-slate-200 rounded-lg p-2.5">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <p className="text-sm font-medium text-slate-700">{dp.metric}</p>
                  <p className="text-sm text-blue-600 font-semibold">{dp.value}</p>
                </div>
                <ConfidenceBadge level={dp.confidence} />
              </div>
              <div className="flex items-center gap-2 mt-1.5 text-xs text-slate-400">
                <span>{dp.source}</span>
                {dp.notes && <span>- {dp.notes}</span>}
              </div>
            </div>
          ))}
        </div>
      )}

      {card.gaps.length > 0 && (
        <div className="space-y-2">
          <h5 className="text-xs font-medium text-slate-400 uppercase tracking-wide">Data Gaps</h5>
          {card.gaps.map((gap, i) => (
            <GapFlag key={i} gap={gap} />
          ))}
        </div>
      )}
    </div>
  );
}
TSEOF

# ======================== UPDATED NODE DETAIL PANEL — add data card ========================
cat > apps/web/src/components/tree/NodeDetailPanel.tsx << 'TSEOF'
import type { HypothesisNode } from '@/types/hypothesis';
import { depthColor } from '@/lib/utils';
import { TestabilityBadge } from '@/components/analysis/TestabilityBadge';
import { DataCardView } from '@/components/data-cards/DataCard';

interface Props {
  node: HypothesisNode | null;
  onClose: () => void;
}

export function NodeDetailPanel({ node, onClose }: Props) {
  if (!node) return null;

  const priority = node.testability
    ? node.testability.impact_score *
      node.testability.testability_score *
      node.testability.data_availability_score
    : null;

  return (
    <div className="fixed right-0 top-0 h-full w-[440px] bg-white shadow-xl border-l border-slate-200 p-6 overflow-y-auto z-50">
      <div className="flex justify-between items-start mb-4">
        <div className="flex items-center gap-2">
          <div className={`w-3 h-3 rounded-full ${depthColor(node.depth)}`} />
          <span className="text-xs font-mono text-slate-400">Depth {node.depth}</span>
          {node.is_leaf && (
            <span className="text-xs bg-emerald-100 text-emerald-700 px-2 py-0.5 rounded-full">Leaf</span>
          )}
        </div>
        <button onClick={onClose} className="text-slate-400 hover:text-slate-600 text-xl leading-none">&times;</button>
      </div>

      <h3 className="text-lg font-semibold text-slate-800 mb-4">{node.statement}</h3>

      {node.testability && (
        <div className="mb-4 p-3 bg-slate-50 rounded-lg">
          <div className="flex items-center justify-between mb-2">
            <h4 className="text-sm font-medium text-slate-500">Testability</h4>
            <TestabilityBadge classification={node.testability.classification} />
          </div>
          <p className="text-sm text-slate-600 mb-2">{node.testability.rationale}</p>
          <div className="grid grid-cols-3 gap-2 text-center">
            <div>
              <p className="text-xs text-slate-400">Impact</p>
              <p className="text-sm font-semibold text-slate-700">{node.testability.impact_score}/5</p>
            </div>
            <div>
              <p className="text-xs text-slate-400">Testability</p>
              <p className="text-sm font-semibold text-slate-700">{node.testability.testability_score}/3</p>
            </div>
            <div>
              <p className="text-xs text-slate-400">Data Avail.</p>
              <p className="text-sm font-semibold text-slate-700">{node.testability.data_availability_score}/3</p>
            </div>
          </div>
          {priority !== null && (
            <p className="text-xs text-slate-400 mt-2 text-center">Priority Score: {priority}</p>
          )}
        </div>
      )}

      {node.analysis && (
        <div className="mb-4 p-3 bg-blue-50 rounded-lg">
          <h4 className="text-sm font-medium text-slate-500 mb-2">Proposed Analysis</h4>
          <p className="text-sm font-semibold text-slate-700 mb-1">
            {node.analysis.analysis_type.replace(/_/g, ' ')}
          </p>
          <p className="text-sm text-slate-600 mb-2">{node.analysis.methodology}</p>
          <div className="mb-2">
            <p className="text-xs font-medium text-slate-500 mb-1">Data Sources</p>
            <div className="flex flex-wrap gap-1">
              {node.analysis.data_sources.map((src, i) => (
                <span key={i} className="text-xs bg-white text-slate-600 px-1.5 py-0.5 rounded border border-slate-200">{src}</span>
              ))}
            </div>
          </div>
          <div className="flex justify-between text-xs text-slate-500 mt-2">
            <span>Output: {node.analysis.output_format}</span>
            <span>LOE: {node.analysis.loe_hours}h</span>
          </div>
        </div>
      )}

      {node.data_card && (
        <div className="mb-4">
          <DataCardView card={node.data_card} />
        </div>
      )}

      {node.what_must_be_true && (
        <div className="mb-4">
          <h4 className="text-sm font-medium text-slate-500 mb-1">What Must Be True</h4>
          <p className="text-sm text-slate-700 bg-slate-50 p-3 rounded-lg">{node.what_must_be_true}</p>
        </div>
      )}

      {node.evidence_needed && (
        <div className="mb-4">
          <h4 className="text-sm font-medium text-slate-500 mb-1">Evidence Needed</h4>
          <p className="text-sm text-slate-700 bg-slate-50 p-3 rounded-lg">{node.evidence_needed}</p>
        </div>
      )}

      <div className="text-xs text-slate-400 mt-6">
        ID: {node.id} &middot; Children: {node.children.length}
      </div>
    </div>
  );
}
TSEOF

# ======================== UPDATED TREE VIEW — data indicator ========================
cat > apps/web/src/components/tree/HypothesisTree.tsx << 'TSEOF'
import { useState } from 'react';
import type { HypothesisNode as HNode } from '@/types/hypothesis';
import { NodeDetailPanel } from './NodeDetailPanel';
import { TestabilityBadge } from '@/components/analysis/TestabilityBadge';
import { depthColor, cn } from '@/lib/utils';

interface TreeNodeProps {
  node: HNode;
  onSelect: (node: HNode) => void;
  selectedId: string | null;
}

function TreeNode({ node, onSelect, selectedId }: TreeNodeProps) {
  const [collapsed, setCollapsed] = useState(false);
  const hasChildren = node.children.length > 0;
  const isSelected = node.id === selectedId;
  const hasData = node.data_card && node.data_card.data_points.length > 0;
  const hasGaps = node.data_card && node.data_card.gaps.length > 0;

  return (
    <div className="ml-4 first:ml-0">
      <div
        className={cn(
          'flex items-start gap-2 p-3 rounded-lg mb-1 cursor-pointer transition-all border',
          isSelected ? 'border-blue-400 bg-blue-50 shadow-sm' : 'border-transparent hover:bg-slate-50'
        )}
        onClick={() => onSelect(node)}
      >
        {hasChildren && (
          <button
            onClick={(e) => { e.stopPropagation(); setCollapsed(!collapsed); }}
            className="mt-0.5 text-slate-400 hover:text-slate-600 text-sm flex-shrink-0 w-5 text-center"
          >
            {collapsed ? '\u25B8' : '\u25BE'}
          </button>
        )}
        {!hasChildren && <div className="w-5 flex-shrink-0" />}
        <div className={`w-2 h-2 rounded-full mt-1.5 flex-shrink-0 ${depthColor(node.depth)}`} />
        <div className="min-w-0 flex-1">
          <p className="text-sm text-slate-800 leading-snug">{node.statement}</p>
          <div className="flex gap-2 mt-1 items-center flex-wrap">
            <span className="text-xs text-slate-400 font-mono">d{node.depth}</span>
            {node.is_leaf && <span className="text-xs bg-emerald-100 text-emerald-700 px-1.5 rounded">leaf</span>}
            {node.testability && <TestabilityBadge classification={node.testability.classification} />}
            {node.analysis && (
              <span className="text-xs bg-slate-100 text-slate-500 px-1.5 rounded">
                {node.analysis.analysis_type.replace(/_/g, ' ')}
              </span>
            )}
            {hasData && (
              <span className="text-xs bg-blue-100 text-blue-600 px-1.5 rounded">
                {node.data_card!.data_points.length} data pts
              </span>
            )}
            {hasGaps && !hasData && (
              <span className="text-xs bg-amber-100 text-amber-600 px-1.5 rounded">
                {node.data_card!.gaps.length} gaps
              </span>
            )}
          </div>
        </div>
      </div>
      {hasChildren && !collapsed && (
        <div className="border-l-2 border-slate-200 ml-6">
          {node.children.map((child) => (
            <TreeNode key={child.id} node={child} onSelect={onSelect} selectedId={selectedId} />
          ))}
        </div>
      )}
    </div>
  );
}

interface Props {
  root: HNode;
}

export function HypothesisTreeView({ root }: Props) {
  const [selected, setSelected] = useState<HNode | null>(null);
  return (
    <div className="flex">
      <div className="flex-1 p-4">
        <TreeNode node={root} onSelect={setSelected} selectedId={selected?.id ?? null} />
      </div>
      <NodeDetailPanel node={selected} onClose={() => setSelected(null)} />
    </div>
  );
}
TSEOF

# ======================== UPDATED LOADING STATE ========================
cat > apps/web/src/components/common/LoadingState.tsx << 'TSEOF'
const STEPS = [
  'Classifying question type...',
  'Selecting decomposition framework...',
  'Generating root hypothesis...',
  'Decomposing into sub-hypotheses...',
  'Validating MECE structure...',
  'Classifying testability of leaves...',
  'Designing analysis methodologies...',
  'Fetching financial data from Yahoo Finance...',
  'Searching SEC EDGAR filings...',
  'Matching data to hypotheses...',
  'Scoring data confidence...',
  'Flagging data gaps...',
  'Finalizing hypothesis tree...',
];

export function LoadingState() {
  return (
    <div className="flex flex-col items-center justify-center py-16">
      <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin mb-6" />
      <div className="space-y-2 text-center">
        {STEPS.map((step, i) => (
          <p key={i} className="text-sm text-slate-500 animate-pulse" style={{ animationDelay: `${i * 0.3}s` }}>
            {step}
          </p>
        ))}
      </div>
      <p className="text-xs text-slate-400 mt-6">This typically takes 5-8 minutes with data retrieval</p>
    </div>
  );
}
TSEOF

echo ""
echo "=== Phase 3 files written ==="
echo ""
echo "New features:"
echo "  - Data Retrieval Agent fetches real data from Yahoo Finance and SEC EDGAR"
echo "  - Each quantitative/already-answered leaf gets a Data Card with:"
echo "    - Data points with metric, value, source, and confidence level (high/medium/low)"
echo "    - Data gaps explicitly flagged with why they matter and alternatives"
echo "  - Tree view shows '3 data pts' or '2 gaps' badges on each leaf"
echo "  - Node detail panel shows full data card with confidence badges and gap flags"
echo ""
echo "Restart backend and generate a new tree. Try a public company question like:"
echo "  Industry: Semiconductor"
echo "  Company: Skyworks"
echo "  Question: Should Skyworks and Qorvo merge?"
echo ""
echo "Yahoo Finance will pull real financials for SWKS and QRVO."