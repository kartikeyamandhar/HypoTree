"""Workplan Compiler + Negotiation Agent."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.workplan.prompts import WORKPLAN_PROMPT, NEGOTIATION_PROMPT
from packages.agents.workplan.schemas import Workplan, Workstream, WorkItem
from packages.shared.types import HypothesisNode

logger = logging.getLogger(__name__)


class WorkplanAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a strategy consulting workplan manager."

    def compile_workplan(
        self, root: HypothesisNode, industry: str, company: str, question: str,
    ) -> Workplan:
        leaves = self._get_classified_leaves(root)
        if not leaves:
            return Workplan(summary="No classified leaves to build workplan from.")

        hyp_block = "\n".join(
            f"- [{n.id}] {n.statement} | "
            f"type={n.analysis.analysis_type.value if n.analysis else 'none'} | "
            f"loe={n.analysis.loe_hours if n.analysis else 0}h | "
            f"priority={n.testability.priority_score if n.testability else 0}"
            for n in leaves
        )

        prompt = WORKPLAN_PROMPT.format(
            industry=industry, company=company, question=question,
            hypotheses_block=hyp_block,
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        workstreams = []
        node_map = {n.id: n for n in leaves}

        for ws_data in data.get("workstreams", []):
            items = []
            for item_data in ws_data.get("items", []):
                hid = item_data.get("hypothesis_id", "")
                node = node_map.get(hid)
                items.append(WorkItem(
                    hypothesis_id=hid,
                    hypothesis_statement=node.statement if node else "",
                    analysis_type=node.analysis.analysis_type.value if node and node.analysis else "",
                    loe_hours=node.analysis.loe_hours if node and node.analysis else 0,
                    resource_type=item_data.get("resource_type", "analyst"),
                ))

            ws = Workstream(
                id=ws_data.get("id", ""),
                name=ws_data.get("name", ""),
                description=ws_data.get("description", ""),
                items=items,
                total_loe=sum(i.loe_hours for i in items),
                sequence_order=ws_data.get("sequence_order", 1),
                depends_on=ws_data.get("depends_on", []),
            )
            workstreams.append(ws)

        workstreams.sort(key=lambda w: w.sequence_order)
        critical_path = [ws.id for ws in workstreams]

        workplan = Workplan(
            workstreams=workstreams,
            total_loe=sum(ws.total_loe for ws in workstreams),
            estimated_weeks=data.get("estimated_weeks", 4),
            critical_path=critical_path,
            summary=data.get("summary", ""),
        )

        logger.info("Workplan compiled: %d workstreams, %.0fh total, %.0f weeks",
            len(workstreams), workplan.total_loe, workplan.estimated_weeks)
        return workplan

    def negotiate(self, workplan: Workplan, user_request: str) -> Workplan:
        wp_dict = workplan.model_dump()
        prompt = NEGOTIATION_PROMPT.format(
            workplan_json=json.dumps(wp_dict, indent=2, default=str),
            user_request=user_request,
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        workstreams = []
        for ws_data in data.get("workstreams", []):
            items = [WorkItem(**i) for i in ws_data.get("items", [])]
            workstreams.append(Workstream(
                id=ws_data.get("id", ""),
                name=ws_data.get("name", ""),
                description=ws_data.get("description", ""),
                items=items,
                total_loe=sum(i.loe_hours for i in items),
                sequence_order=ws_data.get("sequence_order", 1),
                depends_on=ws_data.get("depends_on", []),
            ))

        return Workplan(
            workstreams=workstreams,
            total_loe=sum(ws.total_loe for ws in workstreams),
            estimated_weeks=data.get("estimated_weeks", workplan.estimated_weeks),
            critical_path=data.get("critical_path", []),
            summary=data.get("summary", ""),
        )

    def _get_classified_leaves(self, node: HypothesisNode) -> list[HypothesisNode]:
        result = []
        def walk(n: HypothesisNode):
            if n.is_leaf and n.testability and n.analysis:
                result.append(n)
            for c in n.children:
                walk(c)
        walk(node)
        return result
