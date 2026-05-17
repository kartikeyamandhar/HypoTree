import type { HypothesisNode } from './hypothesis';

export interface AnalysisPlanRow {
  node: HypothesisNode;
  priorityScore: number;
}

export function getAnalysisPlanRows(root: HypothesisNode): AnalysisPlanRow[] {
  const rows: AnalysisPlanRow[] = [];

  function walk(node: HypothesisNode) {
    if (node.is_leaf && node.testability) {
      const priority =
        node.testability.impact_score *
        node.testability.testability_score *
        node.testability.data_availability_score;
      rows.push({ node, priorityScore: priority });
    }
    for (const child of node.children) {
      walk(child);
    }
  }

  walk(root);
  return rows.sort((a, b) => b.priorityScore - a.priorityScore);
}
