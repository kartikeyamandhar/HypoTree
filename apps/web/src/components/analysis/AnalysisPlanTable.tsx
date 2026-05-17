import { useState, useMemo } from 'react';
import type { HypothesisNode, TestabilityClass } from '@/types/hypothesis';
import { getAnalysisPlanRows } from '@/types/analysis';
import { TestabilityBadge } from './TestabilityBadge';

type SortField = 'priority' | 'loe' | 'impact' | 'type';

export function AnalysisPlanTable({ root }: { root: HypothesisNode }) {
  const [sortField, setSortField] = useState<SortField>('priority');
  const [filterClass, setFilterClass] = useState<TestabilityClass | 'all'>('all');

  const rows = useMemo(() => {
    let r = getAnalysisPlanRows(root);
    if (filterClass !== 'all') r = r.filter((row) => row.node.testability?.classification === filterClass);
    r.sort((a, b) => {
      switch (sortField) {
        case 'priority': return b.priorityScore - a.priorityScore;
        case 'loe': return (a.node.analysis?.loe_hours ?? 0) - (b.node.analysis?.loe_hours ?? 0);
        case 'impact': return (b.node.testability?.impact_score ?? 0) - (a.node.testability?.impact_score ?? 0);
        case 'type': return (a.node.testability?.classification ?? '').localeCompare(b.node.testability?.classification ?? '');
        default: return 0;
      }
    });
    return r;
  }, [root, sortField, filterClass]);

  const totalLOE = rows.reduce((s, r) => s + (r.node.analysis?.loe_hours ?? 0), 0);
  const selectStyle = { background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-secondary)', borderRadius: '8px', padding: '4px 8px', fontSize: '12px' };

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>Analysis Plan</h3>
          <p className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>{rows.length} hypotheses &middot; {totalLOE.toFixed(0)}h total</p>
        </div>
        <div className="flex gap-2">
          <select value={filterClass} onChange={(e) => setFilterClass(e.target.value as TestabilityClass | 'all')} style={selectStyle}>
            <option value="all">All</option><option value="quantitative">Quant</option><option value="qualitative">Qual</option><option value="assumption">Assumption</option><option value="already_answered">Answered</option>
          </select>
          <select value={sortField} onChange={(e) => setSortField(e.target.value as SortField)} style={selectStyle}>
            <option value="priority">Priority</option><option value="loe">LOE</option><option value="impact">Impact</option><option value="type">Type</option>
          </select>
        </div>
      </div>
      <div className="space-y-1">
        {rows.map((row, i) => (
          <div key={row.node.id} className="flex items-center gap-4 py-3 px-4 rounded-lg transition-colors"
            style={{ background: i % 2 === 0 ? 'var(--bg-card)' : 'transparent' }}>
            <span className="text-xs font-mono w-6" style={{ color: 'var(--text-muted)' }}>{i + 1}</span>
            <div className="flex-1 min-w-0">
              <p className="text-sm truncate" style={{ color: 'var(--text-primary)' }}>{row.node.statement}</p>
            </div>
            <TestabilityBadge classification={row.node.testability!.classification} />
            <span className="text-xs font-mono w-8 text-right" style={{ color: 'var(--accent-indigo)' }}>{row.priorityScore}</span>
            <span className="text-xs w-24 truncate" style={{ color: 'var(--text-secondary)' }}>{row.node.analysis?.analysis_type.replace(/_/g, ' ')}</span>
            <span className="text-xs font-mono w-10 text-right" style={{ color: 'var(--text-muted)' }}>{row.node.analysis?.loe_hours ?? 0}h</span>
          </div>
        ))}
      </div>
    </div>
  );
}
