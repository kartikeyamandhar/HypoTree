"""Benchmark Agent — finds comparable cases for assumptions."""
from __future__ import annotations

import json
import logging
from typing import Optional

from packages.agents.base import BaseAgent, _emit
from packages.agents.benchmark.prompts import BENCHMARK_PROMPT
from packages.shared.types import HypothesisNode

logger = logging.getLogger(__name__)


class BenchmarkAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a strategy consulting analyst specializing in comparable case analysis."

    def find_comparables(
        self, node: HypothesisNode, industry: str, company: str, question: str,
        available_data: str = "",
    ) -> Optional[dict]:
        assumption = node.what_must_be_true or node.statement

        _emit("P7", "Benchmark Agent", f"Finding comparables for: {node.statement[:50]}...")

        prompt = BENCHMARK_PROMPT.format(
            industry=industry, company=company, question=question,
            statement=node.statement, assumption=assumption,
            available_data=available_data or "No additional data available.",
        )

        try:
            raw = self.call_llm(prompt)
            data = json.loads(raw)
            _emit("P7", "Benchmark Agent",
                f"Found {len(data.get('comparables', []))} comparables")
            return data
        except Exception as e:
            logger.warning("Benchmark failed for '%s': %s", node.statement[:50], e)
            return None
