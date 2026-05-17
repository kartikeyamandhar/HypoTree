"""Decomposer agent — generates sub-hypotheses for a parent node."""
from __future__ import annotations

import json
import logging
from typing import Optional

from packages.agents.base import BaseAgent
from packages.agents.decomposer.prompts import DECOMPOSE_PROMPT, ISSUES_TEMPLATE
from packages.shared.constants import TARGET_TREE_DEPTH
from packages.shared.types import HypothesisNode, MECEValidationResult

logger = logging.getLogger(__name__)


class DecomposerAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a strategy consulting expert specializing in hypothesis decomposition."

    def decompose(
        self,
        parent: HypothesisNode,
        industry: str,
        company: str,
        question: str,
        previous_issues: Optional[MECEValidationResult] = None,
    ) -> list[HypothesisNode]:
        issues_section = ""
        if previous_issues and not previous_issues.is_valid:
            issues_section = ISSUES_TEMPLATE.format(
                overlaps=", ".join(previous_issues.overlaps) or "none",
                gaps=", ".join(previous_issues.gaps) or "none",
                suggestions=", ".join(previous_issues.suggestions) or "none",
            )

        prompt = DECOMPOSE_PROMPT.format(
            industry=industry,
            company=company,
            question=question,
            parent_statement=parent.statement,
            depth=parent.depth,
            target_depth=TARGET_TREE_DEPTH,
            next_depth=parent.depth + 1,
            issues_section=issues_section,
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        children: list[HypothesisNode] = []
        for child_data in data["children"]:
            child = HypothesisNode(
                statement=child_data["statement"],
                what_must_be_true=child_data.get("what_must_be_true"),
                evidence_needed=child_data.get("evidence_needed"),
            )
            children.append(child)

        logger.info(
            "Decomposed '%s' into %d children", parent.statement[:50], len(children)
        )
        return children
