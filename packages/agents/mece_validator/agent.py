"""MECE Validator agent — adversarial check for mutual exclusivity and collective exhaustiveness."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.mece_validator.prompts import MECE_VALIDATION_PROMPT
from packages.shared.types import HypothesisNode, MECEValidationResult

logger = logging.getLogger(__name__)


def _to_string_list(items: list) -> list[str]:
    """Convert a list of strings or dicts to a list of strings."""
    result = []
    for item in items:
        if isinstance(item, str):
            result.append(item)
        elif isinstance(item, dict):
            result.append(item.get("description", item.get("detail", str(item))))
        else:
            result.append(str(item))
    return result


class MECEValidatorAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a practical MECE validator for strategy consulting."

    def validate(
        self, parent: HypothesisNode, children: list[HypothesisNode]
    ) -> MECEValidationResult:
        siblings_list = "\n".join(
            f"  {i + 1}. {child.statement}" for i, child in enumerate(children)
        )

        prompt = MECE_VALIDATION_PROMPT.format(
            parent_statement=parent.statement,
            siblings_list=siblings_list,
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        result = MECEValidationResult(
            is_valid=data["is_valid"],
            overlaps=_to_string_list(data.get("overlaps", [])),
            gaps=_to_string_list(data.get("gaps", [])),
            suggestions=_to_string_list(data.get("suggestions", [])),
        )

        logger.info(
            "MECE validation for '%s': valid=%s overlaps=%d gaps=%d",
            parent.statement[:50],
            result.is_valid,
            len(result.overlaps),
            len(result.gaps),
        )
        return result
