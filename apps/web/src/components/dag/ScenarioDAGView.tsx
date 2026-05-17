import { useState, useCallback } from 'react';
import type { HypothesisTree, HypothesisNode, HypothesisState, CausalDAG } from '@/types/hypothesis';
import { api } from '@/lib/api';

const SS: Record<HypothesisState, { bg: string; border: string; text: string; label: string }> = {
  true: { bg: '#0a1f0a', border: '#166534', text: '#4ade80', label: 'TRUE' },
  false: { bg: '#1c0a0a', border: '#7f1d1d', text: '#f87171', label: 'FALSE' },
  uncertain: { bg: 'var(--bg-card)', border: 'var(--border-subtle)', text: 'var(--text-muted)', label: '?' },
};

function collectAll(n: HypothesisNode): HypothesisNode[] { return [n, ...n.children.flatMap(collectAll)]; }

export function ScenarioDAGView({ tree, projectId }: { tree: HypothesisTree; projectId: string }) {
  const [dag, setDag] = useState<CausalDAG | null>(tree.causal_dag);
  const [toggling, setToggling] = useState<string | null>(null);
  const nodes = collectAll(tree.root).filter((n) => n.depth <= 2);

  const handleToggle = useCallback(async (id: string, state: HypothesisState) => {
    setToggling(id);
    try {
      const r = await api.toggleNode(projectId, id, state);
      setDag((p) => p ? { ...p, node_states: r.node_states as Record<string, HypothesisState>, node_probabilities: r.node_probabilities } : null);
    } finally { setToggling(null); }
  }, [projectId]);

  const cycle = (s: HypothesisState): HypothesisState => s === 'uncertain' ? 'true' : s === 'true' ? 'false' : 'uncertain';
  if (!dag) return null;

  return (
    <div>
      <h3 className="text-lg font-semibold mb-1" style={{ color: 'var(--text-primary)' }}>Scenario Modeling</h3>
      <p className="text-xs mb-4" style={{ color: 'var(--text-muted)' }}>Click to toggle: ? {'\u2192'} TRUE {'\u2192'} FALSE {'\u2192'} ?</p>
      <div className="space-y-1">
        {nodes.map((n) => {
          const st = (dag.node_states[n.id] ?? 'uncertain') as HypothesisState;
          const prob = dag.node_probabilities[n.id] ?? 0.5;
          const s = SS[st];
          return (
            <div key={n.id} className="flex items-center gap-3 py-2.5 px-3 rounded-lg cursor-pointer transition-all"
              style={{ marginLeft: n.depth * 20, background: s.bg, border: `1px solid ${s.border}`, opacity: toggling === n.id ? 0.5 : 1 }}
              onClick={() => !toggling && handleToggle(n.id, cycle(st))}>
              <span className="text-xs font-mono font-bold w-14 text-center py-0.5 rounded" style={{ color: s.text, border: `1px solid ${s.border}` }}>{s.label}</span>
              <p className="flex-1 text-sm" style={{ color: 'var(--text-primary)' }}>{n.statement}</p>
              <div className="w-16">
                <div className="h-1.5 rounded-full" style={{ background: 'var(--bg-primary)' }}>
                  <div className="h-1.5 rounded-full transition-all duration-500" style={{ width: `${prob * 100}%`, background: prob >= 0.7 ? '#22c55e' : prob <= 0.3 ? '#ef4444' : '#f59e0b' }} />
                </div>
                <p className="text-xs text-center mt-0.5 font-mono" style={{ color: 'var(--text-muted)', fontSize: '10px' }}>{(prob * 100).toFixed(0)}%</p>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
