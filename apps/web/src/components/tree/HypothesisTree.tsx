import { useState } from 'react';
import type { HypothesisNode as HNode } from '@/types/hypothesis';
import { NodeDetailPanel } from './NodeDetailPanel';
import { TestabilityBadge } from '@/components/analysis/TestabilityBadge';

const DEPTH_DOTS = ['#6366f1', '#3b82f6', '#22c55e', '#f59e0b'];

interface TreeNodeProps { node: HNode; onSelect: (n: HNode) => void; selectedId: string | null; }

function TreeNode({ node, onSelect, selectedId }: TreeNodeProps) {
  const [collapsed, setCollapsed] = useState(node.depth >= 2);
  const has = node.children.length > 0;
  const sel = node.id === selectedId;
  const dot = DEPTH_DOTS[node.depth % DEPTH_DOTS.length];

  return (
    <div style={{ marginLeft: node.depth > 0 ? 16 : 0 }}>
      <div onClick={() => onSelect(node)}
        className="flex items-start gap-2 py-2 px-3 rounded-lg cursor-pointer transition-all duration-150"
        style={{ background: sel ? 'var(--bg-card)' : 'transparent', border: sel ? '1px solid var(--border-active)' : '1px solid transparent' }}>
        {has ? (
          <button onClick={(e) => { e.stopPropagation(); setCollapsed(!collapsed); }}
            className="mt-1 text-xs w-4 flex-shrink-0 text-center" style={{ color: 'var(--text-muted)' }}>
            {collapsed ? '\u25B8' : '\u25BE'}
          </button>
        ) : <div className="w-4 flex-shrink-0" />}
        <div className="w-2 h-2 rounded-full mt-1.5 flex-shrink-0" style={{ background: dot }} />
        <div className="flex-1 min-w-0">
          <p className="text-sm leading-snug" style={{ color: 'var(--text-primary)' }}>{node.statement}</p>
          <div className="flex gap-1.5 mt-1 items-center flex-wrap">
            {node.is_leaf && <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: '#132b1a', color: '#4ade80', fontSize: '10px' }}>leaf</span>}
            {node.testability && <TestabilityBadge classification={node.testability.classification} />}
            {node.data_card && node.data_card.data_points.length > 0 && (
              <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: '#1a2332', color: '#60a5fa', fontSize: '10px' }}>{node.data_card.data_points.length} data</span>
            )}
            {node.stress_test_severity && (
              <span className="w-2 h-2 rounded-full" style={{ background: node.stress_test_severity === 'critical' ? '#ef4444' : node.stress_test_severity === 'warning' ? '#f59e0b' : '#3b82f6' }} />
            )}
          </div>
        </div>
      </div>
      {has && !collapsed && (
        <div className="ml-3" style={{ borderLeft: '1px solid var(--border-subtle)' }}>
          {node.children.map((c) => <TreeNode key={c.id} node={c} onSelect={onSelect} selectedId={selectedId} />)}
        </div>
      )}
    </div>
  );
}

export function HypothesisTreeView({ root, projectId }: { root: HNode; projectId?: string }) {
  const [selected, setSelected] = useState<HNode | null>(null);
  return (
    <div className="flex gap-4">
      <div className="flex-1 overflow-auto" style={{ maxHeight: 'calc(100vh - 200px)' }}>
        <TreeNode node={root} onSelect={setSelected} selectedId={selected?.id ?? null} />
      </div>
      {selected && <NodeDetailPanel node={selected} onClose={() => setSelected(null)} projectId={projectId} />}
    </div>
  );
}
