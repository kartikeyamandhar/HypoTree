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
