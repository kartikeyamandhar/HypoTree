"""Analysis Designer agent — proposes methodology per testable hypothesis."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.analysis_designer.prompts import ANALYSIS_DESIGN_PROMPT
from packages.shared.types import AnalysisDesign, AnalysisType, HypothesisNode, TestabilityResult

logger = logging.getLogger(__name__)


class AnalysisDesignerAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a strategy consulting analyst specializing in analysis design and methodology."

    def design(
        self,
        node: HypothesisNode,
        testability: TestabilityResult,
        industry: str,
        company: str,
        question: str,
    ) -> AnalysisDesign:
        prompt = ANALYSIS_DESIGN_PROMPT.format(
            industry=industry,
            company=company,
            question=question,
            testability_class=testability.classification.value,
            statement=node.statement,
            what_must_be_true=node.what_must_be_true or "Not specified",
            evidence_needed=node.evidence_needed or "Not specified",
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        # Safely parse analysis_type
        try:
            analysis_type = AnalysisType(data["analysis_type"])
        except ValueError:
            analysis_type = AnalysisType.DATA_ANALYSIS

        result = AnalysisDesign(
            analysis_type=analysis_type,
            methodology=data.get("methodology", ""),
            data_sources=data.get("data_sources", []),
            output_format=data.get("output_format", ""),
            loe_hours=data.get("loe_hours", 8.0),
            rationale=data.get("rationale", ""),
        )

        logger.info(
            "Designed analysis for '%s': %s (%.0fh LOE)",
            node.statement[:50],
            result.analysis_type.value,
            result.loe_hours,
        )
        return result
