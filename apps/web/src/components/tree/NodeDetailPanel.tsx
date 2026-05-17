import { useState } from 'react';
import type { HypothesisNode } from '@/types/hypothesis';
import { TestabilityBadge } from '@/components/analysis/TestabilityBadge';
import { DataCardView } from '@/components/data-cards/DataCard';
import { api } from '@/lib/api';

interface Props { node: HypothesisNode; onClose: () => void; projectId?: string; }

const OUTCOMES = [
  { value: 'correct', label: 'Correct', color: '#22c55e', icon: '\u2713' },
  { value: 'incorrect', label: 'Incorrect', color: '#ef4444', icon: '\u2717' },
  { value: 'irrelevant', label: 'Irrelevant', color: '#f59e0b', icon: '\u2212' },
  { value: 'missing', label: 'Missing Context', color: '#6366f1', icon: '?' },
];

export function NodeDetailPanel({ node, onClose, projectId }: Props) {
  const [feedbackSent, setFeedbackSent] = useState(false);
  const priority = node.testability ? node.testability.impact_score * node.testability.testability_score * node.testability.data_availability_score : null;

  const handleFeedback = async (outcome: string) => {
    if (!projectId) return;
    try {
      await api.submitFeedback(projectId, node.id, outcome);
      setFeedbackSent(true);
    } catch (e) { console.error(e); }
  };

  return (
    <div className="w-[400px] flex-shrink-0 rounded-xl overflow-y-auto" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', maxHeight: 'calc(100vh - 200px)' }}>
      <div className="p-5">
        <div className="flex justify-between items-start mb-3">
          <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>d{node.depth} &middot; {node.id}</span>
          <button onClick={onClose} className="text-lg leading-none" style={{ color: 'var(--text-muted)' }}>&times;</button>
        </div>

        <h3 className="text-base font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>{node.statement}</h3>

        {node.testability && (
          <div className="mb-4 p-3 rounded-lg" style={{ background: 'var(--bg-secondary)' }}>
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>TESTABILITY</span>
              <TestabilityBadge classification={node.testability.classification} />
            </div>
            <p className="text-xs mb-2" style={{ color: 'var(--text-secondary)' }}>{node.testability.rationale}</p>
            <div className="grid grid-cols-4 gap-2 text-center">
              {[{ l: 'Impact', v: `${node.testability.impact_score}/5` }, { l: 'Test', v: `${node.testability.testability_score}/3` },
                { l: 'Data', v: `${node.testability.data_availability_score}/3` }, { l: 'Priority', v: String(priority ?? '-') }].map((m) => (
                <div key={m.l}><p className="text-xs" style={{ color: 'var(--text-muted)' }}>{m.l}</p><p className="text-sm font-semibold font-mono" style={{ color: 'var(--text-primary)' }}>{m.v}</p></div>
              ))}
            </div>
          </div>
        )}

        {node.analysis && (
          <div className="mb-4 p-3 rounded-lg" style={{ background: 'var(--bg-secondary)' }}>
            <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>ANALYSIS</span>
            <p className="text-sm font-semibold mt-1" style={{ color: 'var(--accent-indigo)' }}>{node.analysis.analysis_type.replace(/_/g, ' ')}</p>
            <p className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>{node.analysis.methodology}</p>
            <div className="flex flex-wrap gap-1 mt-2">
              {node.analysis.data_sources.map((s, i) => (
                <span key={i} className="text-xs px-1.5 py-0.5 rounded" style={{ background: 'var(--bg-primary)', color: 'var(--text-muted)', border: '1px solid var(--border-subtle)' }}>{s}</span>
              ))}
            </div>
            <p className="text-xs mt-2 font-mono" style={{ color: 'var(--text-muted)' }}>{node.analysis.loe_hours}h LOE</p>
          </div>
        )}

        {node.data_card && <div className="mb-4"><DataCardView card={node.data_card} /></div>}

        {node.what_must_be_true && (
          <div className="mb-3">
            <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>WHAT MUST BE TRUE</span>
            <p className="text-xs mt-1 p-2 rounded" style={{ background: 'var(--bg-secondary)', color: 'var(--text-secondary)' }}>{node.what_must_be_true}</p>
          </div>
        )}

        {/* Feedback section */}
        {node.is_leaf && projectId && (
          <div className="mt-4 pt-4" style={{ borderTop: '1px solid var(--border-subtle)' }}>
            <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>POST-CASE FEEDBACK</span>
            {feedbackSent ? (
              <p className="text-xs mt-2" style={{ color: 'var(--accent-green)' }}>{'\u2713'} Feedback recorded</p>
            ) : (
              <div className="flex gap-2 mt-2">
                {OUTCOMES.map((o) => (
                  <button key={o.value} onClick={() => handleFeedback(o.value)}
                    className="flex-1 py-1.5 rounded-lg text-xs font-medium transition-colors"
                    style={{ background: o.color + '15', border: `1px solid ${o.color}33`, color: o.color }}>
                    {o.icon} {o.label}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
