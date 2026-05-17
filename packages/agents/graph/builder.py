"""Causal DAG builder — constructs dependency graph from hypothesis tree."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.shared.types import CausalDAG, CausalEdge, HypothesisNode, HypothesisState

logger = logging.getLogger(__name__)

DAG_INFERENCE_PROMPT = """You are a strategy analyst identifying causal dependencies between hypotheses.

Given these hypotheses from a strategy decomposition tree, identify which hypotheses are PREREQUISITES for others. A dependency means: if hypothesis A is FALSE, hypothesis B cannot be TRUE (or becomes significantly less likely).

Only identify strong, logical dependencies. Do not create dependencies between every pair.

Hypotheses:
{hypotheses_block}

Respond ONLY with valid JSON, no markdown fences:
{{
  "edges": [
    {{
      "source_id": "<prerequisite hypothesis id>",
      "target_id": "<dependent hypothesis id>",
      "relationship": "<one sentence describing the dependency>"
    }}
  ]
}}

If no strong dependencies exist, return: {{"edges": []}}"""


class DAGBuilderAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a causal reasoning expert identifying dependencies between strategic hypotheses."

    def build_dag(self, root: HypothesisNode) -> CausalDAG:
        """Build causal DAG from hypothesis tree."""
        all_nodes = self._collect_all(root)

        # Tree edges (parent-child) are inherent dependencies
        tree_edges: list[CausalEdge] = []
        for node in all_nodes:
            for child in node.children:
                tree_edges.append(CausalEdge(
                    source_id=child.id,
                    target_id=node.id,
                    relationship=f"Child hypothesis supports parent",
                    strength=1.0,
                ))

        # Cross-branch dependencies via LLM inference
        # Use depth-1 and depth-2 nodes for cross-branch detection
        mid_nodes = [n for n in all_nodes if 1 <= n.depth <= 2]
        cross_edges = self._infer_cross_dependencies(mid_nodes)

        all_edges = tree_edges + cross_edges

        # Initialize all nodes as uncertain
        node_states: dict[str, HypothesisState] = {}
        node_probs: dict[str, float] = {}
        for node in all_nodes:
            node_states[node.id] = HypothesisState.UNCERTAIN
            node_probs[node.id] = 0.5

        dag = CausalDAG(
            edges=all_edges,
            node_states=node_states,
            node_probabilities=node_probs,
        )

        logger.info("DAG built: %d tree edges, %d cross edges, %d total nodes",
            len(tree_edges), len(cross_edges), len(all_nodes))
        return dag

    def _infer_cross_dependencies(self, nodes: list[HypothesisNode]) -> list[CausalEdge]:
        """Use LLM to identify cross-branch dependencies."""
        if len(nodes) < 2:
            return []

        hypotheses_block = "\n".join(
            f"- [{n.id}] (depth {n.depth}) {n.statement}" for n in nodes
        )

        prompt = DAG_INFERENCE_PROMPT.format(hypotheses_block=hypotheses_block)

        try:
            raw = self.call_llm(prompt)
            data = json.loads(raw)
        except Exception as e:
            logger.warning("Cross-dependency inference failed: %s", str(e))
            return []

        edges = []
        valid_ids = {n.id for n in nodes}
        for edge_data in data.get("edges", []):
            src = edge_data.get("source_id", "")
            tgt = edge_data.get("target_id", "")
            if src in valid_ids and tgt in valid_ids and src != tgt:
                edges.append(CausalEdge(
                    source_id=src,
                    target_id=tgt,
                    relationship=edge_data.get("relationship", ""),
                    strength=0.8,
                ))

        logger.info("Inferred %d cross-branch dependencies", len(edges))
        return edges

    @staticmethod
    def _collect_all(node: HypothesisNode) -> list[HypothesisNode]:
        result = [node]
        for child in node.children:
            result.extend(DAGBuilderAgent._collect_all(child))
        return result
