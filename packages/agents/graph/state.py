"""Belief propagation on causal DAG."""
from __future__ import annotations

from packages.shared.types import CausalDAG, CausalEdge, HypothesisState


def propagate_states(dag: CausalDAG, toggled_id: str, new_state: HypothesisState) -> CausalDAG:
    """Propagate a state change through the DAG. Returns updated DAG."""
    dag.node_states[toggled_id] = new_state

    # Set probability based on state
    if new_state == HypothesisState.TRUE:
        dag.node_probabilities[toggled_id] = 0.95
    elif new_state == HypothesisState.FALSE:
        dag.node_probabilities[toggled_id] = 0.05
    else:
        dag.node_probabilities[toggled_id] = 0.5

    # Build adjacency: for each target, find all sources
    deps: dict[str, list[CausalEdge]] = {}
    for edge in dag.edges:
        if edge.target_id not in deps:
            deps[edge.target_id] = []
        deps[edge.target_id].append(edge)

    # Topological propagation (simplified)
    visited = {toggled_id}
    queue = [toggled_id]

    # Find all nodes that depend on the toggled node (downstream)
    downstream: dict[str, list[str]] = {}
    for edge in dag.edges:
        if edge.source_id not in downstream:
            downstream[edge.source_id] = []
        downstream[edge.source_id].append(edge.target_id)

    while queue:
        current = queue.pop(0)
        for target_id in downstream.get(current, []):
            if target_id in visited:
                continue
            visited.add(target_id)

            # Compute probability from all incoming edges
            incoming = deps.get(target_id, [])
            if incoming:
                # Product of source probabilities (AND logic: all prerequisites needed)
                combined = 1.0
                for edge in incoming:
                    src_prob = dag.node_probabilities.get(edge.source_id, 0.5)
                    combined *= src_prob * edge.strength
                dag.node_probabilities[target_id] = round(min(combined, 0.99), 3)

                # Update state based on probability
                if dag.node_probabilities[target_id] >= 0.7:
                    dag.node_states[target_id] = HypothesisState.TRUE
                elif dag.node_probabilities[target_id] <= 0.3:
                    dag.node_states[target_id] = HypothesisState.FALSE
                else:
                    dag.node_states[target_id] = HypothesisState.UNCERTAIN

            queue.append(target_id)

    return dag


def create_scenario_snapshot(dag: CausalDAG) -> tuple[dict[str, HypothesisState], dict[str, float]]:
    """Capture current DAG state as a scenario snapshot."""
    return dict(dag.node_states), dict(dag.node_probabilities)
