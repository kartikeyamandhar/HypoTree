import { useState, useCallback } from 'react';
import type { HypothesisTree, HypothesisNode, HypothesisState, CausalDAG } from '@/types/hypothesis';
import { api } from '@/lib/api';

function collectAll(n: HypothesisNode): HypothesisNode[] {
  return [n, ...n.children.flatMap(collectAll)];
}

interface Props {
  tree: HypothesisTree;
  projectId: string;
}

export function ScenarioDAGView({ tree, projectId }: Props) {
  const [dag, setDag] = useState<CausalDAG | null>(tree.causal_dag);
  const [toggling, setToggling] = useState<string | null>(null);
  const [expandedBranches, setExpandedBranches] = useState<Set<string>>(new Set());

  const allNodes = collectAll(tree.root);
  const topLevel = tree.root.children;

  const handleToggle = useCallback(async (nodeId: string, newState: HypothesisState) => {
    setToggling(nodeId);
    try {
      const r = await api.toggleNode(projectId, nodeId, newState);
      setDag((p) => p ? {
        ...p,
        node_states: r.node_states as Record<string, HypothesisState>,
        node_probabilities: r.node_probabilities,
      } : null);
    } finally { setToggling(null); }
  }, [projectId]);

  const toggleExpand = (id: string) => {
    setExpandedBranches((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  if (!dag) return <p style={{ color: 'var(--text-muted)' }}>No causal DAG available.</p>;

  const trueCount = Object.values(dag.node_states).filter((s) => s === 'true').length;
  const falseCount = Object.values(dag.node_states).filter((s) => s === 'false').length;
  const uncertainCount = Object.values(dag.node_states).filter((s) => s === 'uncertain').length;

  const handleReset = async () => {
    for (const node of allNodes.filter(n => n.depth <= 2)) {
      await handleToggle(node.id, 'uncertain' as HypothesisState);
    }
  };

  return (
    <div>
      {/* Header */}
      <div className="flex items-start justify-between mb-6">
        <div>
          <h3 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>Scenario Modeling</h3>
          <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
            Set each hypothesis to TRUE or FALSE to see how conclusions change across the tree.
            Probabilities cascade through dependencies automatically.
          </p>
        </div>
        <button onClick={handleReset}
          className="text-xs px-3 py-1.5 rounded-lg"
          style={{ border: '1px solid var(--border-subtle)', color: 'var(--text-muted)' }}>
          Reset All
        </button>
      </div>

      {/* Summary bar */}
      <div className="flex gap-6 mb-6 p-3 rounded-xl" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
        <div className="text-center">
          <p className="text-lg font-semibold" style={{ color: '#4ade80' }}>{trueCount}</p>
          <p className="text-xs" style={{ color: 'var(--text-muted)' }}>TRUE</p>
        </div>
        <div className="text-center">
          <p className="text-lg font-semibold" style={{ color: '#f87171' }}>{falseCount}</p>
          <p className="text-xs" style={{ color: 'var(--text-muted)' }}>FALSE</p>
        </div>
        <div className="text-center">
          <p className="text-lg font-semibold" style={{ color: 'var(--text-secondary)' }}>{uncertainCount}</p>
          <p className="text-xs" style={{ color: 'var(--text-muted)' }}>UNCERTAIN</p>
        </div>
        <div className="text-center ml-auto">
          <p className="text-lg font-semibold" style={{ color: 'var(--accent-indigo)' }}>{dag.edges.length}</p>
          <p className="text-xs" style={{ color: 'var(--text-muted)' }}>Dependencies</p>
        </div>
      </div>

      {/* Hypothesis cards */}
      <div className="space-y-2">
        {topLevel.map((branch) => {
          const branchState = (dag.node_states[branch.id] ?? 'uncertain') as HypothesisState;
          const branchProb = dag.node_probabilities[branch.id] ?? 0.5;
          const expanded = expandedBranches.has(branch.id);
          const branchChildren = branch.children;

          return (
            <div key={branch.id}>
              {/* Branch card */}
              <div className="rounded-xl overflow-hidden" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
                <div className="p-4">
                  <div className="flex items-start gap-4">
                    {/* State buttons */}
                    <div className="flex flex-col gap-1 flex-shrink-0 pt-0.5">
                      <button
                        onClick={() => handleToggle(branch.id, 'true' as HypothesisState)}
                        disabled={toggling === branch.id}
                        className="w-16 py-1 rounded text-xs font-semibold transition-all"
                        style={{
                          background: branchState === 'true' ? '#166534' : 'transparent',
                          border: branchState === 'true' ? '2px solid #22c55e' : '1px solid var(--border-subtle)',
                          color: branchState === 'true' ? '#4ade80' : 'var(--text-muted)',
                          opacity: toggling === branch.id ? 0.4 : 1,
                        }}>
                        TRUE
                      </button>
                      <button
                        onClick={() => handleToggle(branch.id, 'false' as HypothesisState)}
                        disabled={toggling === branch.id}
                        className="w-16 py-1 rounded text-xs font-semibold transition-all"
                        style={{
                          background: branchState === 'false' ? '#7f1d1d' : 'transparent',
                          border: branchState === 'false' ? '2px solid #ef4444' : '1px solid var(--border-subtle)',
                          color: branchState === 'false' ? '#f87171' : 'var(--text-muted)',
                          opacity: toggling === branch.id ? 0.4 : 1,
                        }}>
                        FALSE
                      </button>
                      <button
                        onClick={() => handleToggle(branch.id, 'uncertain' as HypothesisState)}
                        disabled={toggling === branch.id}
                        className="w-16 py-1 rounded text-xs transition-all"
                        style={{
                          background: branchState === 'uncertain' ? 'var(--bg-secondary)' : 'transparent',
                          border: branchState === 'uncertain' ? '2px solid var(--text-muted)' : '1px solid transparent',
                          color: 'var(--text-muted)',
                          opacity: toggling === branch.id ? 0.4 : 1,
                        }}>
                        RESET
                      </button>
                    </div>

                    {/* Content */}
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{branch.statement}</p>

                      {/* Probability bar */}
                      <div className="flex items-center gap-3 mt-3">
                        <div className="flex-1 h-2 rounded-full overflow-hidden" style={{ background: 'var(--bg-primary)' }}>
                          <div className="h-full rounded-full transition-all duration-700 ease-out"
                            style={{
                              width: `${branchProb * 100}%`,
                              background: branchProb >= 0.7 ? '#22c55e' : branchProb <= 0.3 ? '#ef4444' : '#f59e0b',
                            }} />
                        </div>
                        <span className="text-sm font-mono w-12 text-right" style={{
                          color: branchProb >= 0.7 ? '#4ade80' : branchProb <= 0.3 ? '#f87171' : '#fbbf24',
                        }}>
                          {(branchProb * 100).toFixed(0)}%
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Expand children */}
                  {branchChildren.length > 0 && (
                    <button onClick={() => toggleExpand(branch.id)}
                      className="mt-3 text-xs flex items-center gap-1"
                      style={{ color: 'var(--text-muted)' }}>
                      {expanded ? '\u25BE' : '\u25B8'} {branchChildren.length} sub-hypotheses
                    </button>
                  )}
                </div>

                {/* Children */}
                {expanded && (
                  <div style={{ borderTop: '1px solid var(--border-subtle)' }}>
                    {branchChildren.map((child) => {
                      const childState = (dag.node_states[child.id] ?? 'uncertain') as HypothesisState;
                      const childProb = dag.node_probabilities[child.id] ?? 0.5;

                      return (
                        <div key={child.id} className="flex items-center gap-4 px-4 py-3"
                          style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                          {/* Compact state buttons */}
                          <div className="flex gap-1 flex-shrink-0">
                            <button onClick={() => handleToggle(child.id, 'true' as HypothesisState)}
                              className="w-7 h-7 rounded text-xs font-bold transition-all"
                              style={{
                                background: childState === 'true' ? '#166534' : 'transparent',
                                border: childState === 'true' ? '2px solid #22c55e' : '1px solid var(--border-subtle)',
                                color: childState === 'true' ? '#4ade80' : 'var(--text-muted)',
                              }}>
                              T
                            </button>
                            <button onClick={() => handleToggle(child.id, 'false' as HypothesisState)}
                              className="w-7 h-7 rounded text-xs font-bold transition-all"
                              style={{
                                background: childState === 'false' ? '#7f1d1d' : 'transparent',
                                border: childState === 'false' ? '2px solid #ef4444' : '1px solid var(--border-subtle)',
                                color: childState === 'false' ? '#f87171' : 'var(--text-muted)',
                              }}>
                              F
                            </button>
                            <button onClick={() => handleToggle(child.id, 'uncertain' as HypothesisState)}
                              className="w-7 h-7 rounded text-xs transition-all"
                              style={{
                                border: childState === 'uncertain' ? '2px solid var(--text-muted)' : '1px solid transparent',
                                color: 'var(--text-muted)',
                              }}>
                              ?
                            </button>
                          </div>

                          <p className="flex-1 text-sm min-w-0" style={{ color: 'var(--text-secondary)' }}>
                            {child.statement}
                          </p>

                          <div className="flex items-center gap-2 flex-shrink-0 w-24">
                            <div className="flex-1 h-1.5 rounded-full" style={{ background: 'var(--bg-primary)' }}>
                              <div className="h-1.5 rounded-full transition-all duration-700"
                                style={{
                                  width: `${childProb * 100}%`,
                                  background: childProb >= 0.7 ? '#22c55e' : childProb <= 0.3 ? '#ef4444' : '#f59e0b',
                                }} />
                            </div>
                            <span className="text-xs font-mono w-8 text-right" style={{ color: 'var(--text-muted)' }}>
                              {(childProb * 100).toFixed(0)}%
                            </span>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
