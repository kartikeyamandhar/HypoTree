"""Testability Classifier agent — tags each leaf hypothesis with testability class + priority score."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.testability_classifier.prompts import TESTABILITY_PROMPT
from packages.shared.types import HypothesisNode, TestabilityClass, TestabilityResult

logger = logging.getLogger(__name__)


class TestabilityClassifierAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a strategy consulting analyst specializing in hypothesis testability assessment."

    def classify(
        self,
        node: HypothesisNode,
        industry: str,
        company: str,
        question: str,
    ) -> TestabilityResult:
        prompt = TESTABILITY_PROMPT.format(
            industry=industry,
            company=company,
            question=question,
            statement=node.statement,
            what_must_be_true=node.what_must_be_true or "Not specified",
            evidence_needed=node.evidence_needed or "Not specified",
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        result = TestabilityResult(
            classification=TestabilityClass(data["classification"]),
            confidence=data.get("confidence", 0.8),
            rationale=data.get("rationale", ""),
            impact_score=max(1, min(5, data.get("impact_score", 3))),
            testability_score=max(1, min(3, data.get("testability_score", 2))),
            data_availability_score=max(1, min(3, data.get("data_availability_score", 2))),
        )

        logger.info(
            "Classified '%s': %s (impact=%d test=%d data=%d priority=%.0f)",
            node.statement[:50],
            result.classification.value,
            result.impact_score,
            result.testability_score,
            result.data_availability_score,
            result.priority_score,
        )
        return result
