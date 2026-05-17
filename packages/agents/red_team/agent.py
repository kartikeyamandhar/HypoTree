"""Red Team Agent — adversarial stress-testing of hypothesis trees."""
from __future__ import annotations

import json
import logging
from itertools import combinations

from packages.agents.base import BaseAgent
from packages.agents.red_team.prompts import (
    ASSUMPTION_SURFACER_PROMPT,
    CONTRADICTION_PROMPT,
    DEVILS_ADVOCATE_PROMPT,
    SENSITIVITY_PROMPT,
)
from packages.shared.types import (
    Critique,
    CritiqueSeverity,
    CritiqueType,
    HypothesisNode,
    HypothesisTree,
    StressTestReport,
    TestabilityClass,
)

logger = logging.getLogger(__name__)


class RedTeamAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are an adversarial Red Team analyst for strategy consulting."

    def _format_hypotheses(self, nodes: list[HypothesisNode]) -> str:
        lines = []
        for n in nodes:
            data_summary = ""
            if n.data_card and n.data_card.data_points:
                pts = "; ".join(f"{d.metric}: {d.value}" for d in n.data_card.data_points[:3])
                data_summary = f" [Data: {pts}]"
            lines.append(f"- [{n.id}] {n.statement}{data_summary}")
        return "\n".join(lines)

    def _format_pairs(self, pairs: list[tuple[HypothesisNode, HypothesisNode]]) -> str:
        lines = []
        for a, b in pairs:
            lines.append(f"Pair:\n  A [{a.id}]: {a.statement}\n  B [{b.id}]: {b.statement}")
        return "\n\n".join(lines)

    def _parse_critiques(self, raw: str, critique_type: CritiqueType, nodes_map: dict[str, HypothesisNode]) -> list[Critique]:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            logger.warning("Failed to parse red team response")
            return []

        critiques = []
        for c in data.get("critiques", []):
            target_id = c.get("target_node_id", "")
            target_node = nodes_map.get(target_id)
            related_id = c.get("related_node_id")
            related_node = nodes_map.get(related_id, None) if related_id else None

            try:
                severity = CritiqueSeverity(c.get("severity", "note"))
            except ValueError:
                severity = CritiqueSeverity.NOTE

            critiques.append(Critique(
                critique_type=critique_type,
                severity=severity,
                target_node_id=target_id,
                target_node_statement=target_node.statement if target_node else "",
                related_node_id=related_id or "",
                related_node_statement=related_node.statement if related_node else "",
                claim_challenged=c.get("claim_challenged", ""),
                evidence_basis=c.get("evidence_basis", ""),
                suggested_resolution=c.get("suggested_resolution", ""),
                breakpoint_info=c.get("breakpoint_info"),
            ))
        return critiques

    def stress_test(self, tree: HypothesisTree) -> StressTestReport:
        logger.info("Starting stress test...")
        all_nodes = tree.get_all_nodes()
        leaves = tree.get_leaf_nodes()
        nodes_map = {n.id: n for n in all_nodes}

        all_critiques: list[Critique] = []

        # 1. Devil's Advocate — top 10 by priority
        high_impact = sorted(
            [l for l in leaves if l.testability],
            key=lambda n: n.testability.priority_score if n.testability else 0,
            reverse=True,
        )[:10]

        if high_impact:
            logger.info("Running Devil's Advocate on %d hypotheses", len(high_impact))
            prompt = DEVILS_ADVOCATE_PROMPT.format(
                industry=tree.industry, company=tree.company, question=tree.question,
                hypotheses_block=self._format_hypotheses(high_impact),
            )
            raw = self.call_llm(prompt)
            all_critiques.extend(self._parse_critiques(raw, CritiqueType.DEVILS_ADVOCATE, nodes_map))

        # 2. Assumption Surfacer — all leaves
        if leaves:
            # Process in batches of 12
            for i in range(0, len(leaves), 12):
                batch = leaves[i:i+12]
                logger.info("Running Assumption Surfacer on batch %d (%d hypotheses)", i // 12 + 1, len(batch))
                prompt = ASSUMPTION_SURFACER_PROMPT.format(
                    industry=tree.industry, company=tree.company, question=tree.question,
                    hypotheses_block=self._format_hypotheses(batch),
                )
                raw = self.call_llm(prompt)
                all_critiques.extend(self._parse_critiques(raw, CritiqueType.HIDDEN_ASSUMPTION, nodes_map))

        # 3. Sensitivity Analyzer — quantitative leaves with data
        quant_with_data = [
            l for l in leaves
            if l.testability
            and l.testability.classification == TestabilityClass.QUANTITATIVE
            and l.data_card
            and l.data_card.data_points
        ]
        if quant_with_data:
            logger.info("Running Sensitivity Analyzer on %d hypotheses", len(quant_with_data))
            prompt = SENSITIVITY_PROMPT.format(
                industry=tree.industry, company=tree.company, question=tree.question,
                hypotheses_block=self._format_hypotheses(quant_with_data),
            )
            raw = self.call_llm(prompt)
            all_critiques.extend(self._parse_critiques(raw, CritiqueType.SENSITIVITY, nodes_map))

        # 4. Contradiction Detector — pairwise on first-level branches
        first_level = [c for c in tree.root.children]
        if len(first_level) >= 2:
            # Get representative leaves from each branch
            branch_reps: list[HypothesisNode] = []
            for branch in first_level:
                branch_leaves = [n for n in self._collect_all(branch) if n.is_leaf]
                if branch_leaves:
                    # Pick highest-impact leaf from each branch
                    best = max(
                        branch_leaves,
                        key=lambda n: n.testability.priority_score if n.testability else 0,
                    )
                    branch_reps.append(best)

            if len(branch_reps) >= 2:
                pairs = list(combinations(branch_reps, 2))[:10]
                logger.info("Running Contradiction Detector on %d pairs", len(pairs))
                prompt = CONTRADICTION_PROMPT.format(
                    industry=tree.industry, company=tree.company, question=tree.question,
                    pairs_block=self._format_pairs(pairs),
                )
                raw = self.call_llm(prompt)
                all_critiques.extend(self._parse_critiques(raw, CritiqueType.CONTRADICTION, nodes_map))

        # Build report
        report = StressTestReport(critiques=all_critiques)
        report.compute_counts()

        # Tag nodes with worst severity
        severity_order = {CritiqueSeverity.CRITICAL: 3, CritiqueSeverity.WARNING: 2, CritiqueSeverity.NOTE: 1}
        for critique in all_critiques:
            node = nodes_map.get(critique.target_node_id)
            if node:
                current = severity_order.get(node.stress_test_severity, 0) if node.stress_test_severity else 0
                new = severity_order.get(critique.severity, 0)
                if new > current:
                    node.stress_test_severity = critique.severity

        report.summary = (
            f"Stress test complete: {report.critical_count} critical, "
            f"{report.warning_count} warnings, {report.note_count} notes "
            f"across {len(all_critiques)} total critiques."
        )

        logger.info(report.summary)
        return report

    @staticmethod
    def _collect_all(node: HypothesisNode) -> list[HypothesisNode]:
        result = [node]
        for child in node.children:
            result.extend(RedTeamAgent._collect_all(child))
        return result
