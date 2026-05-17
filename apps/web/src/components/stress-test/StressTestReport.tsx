import { useState } from 'react';
import type { StressTestReport as Report, Critique, CritiqueSeverity, CritiqueType } from '@/types/hypothesis';

const SEV: Record<CritiqueSeverity, { bg: string; border: string; text: string; icon: string }> = {
  critical: { bg: '#1c1012', border: '#7f1d1d', text: '#fca5a5', icon: '\u2716' },
  warning: { bg: '#1c1a0e', border: '#78350f', text: '#fcd34d', icon: '\u26A0' },
  note: { bg: '#0e1624', border: '#1e3a5f', text: '#93c5fd', icon: '\u2139' },
};
const TYPES: Record<CritiqueType, string> = { devils_advocate: "Devil's Advocate", hidden_assumption: 'Hidden Assumption', sensitivity: 'Sensitivity', contradiction: 'Contradiction' };

export function StressTestReportView({ report }: { report: Report }) {
  const [fs, setFs] = useState<CritiqueSeverity | 'all'>('all');
  const [ft, setFt] = useState<CritiqueType | 'all'>('all');
  const filtered = report.critiques.filter((c) => (fs === 'all' || c.severity === fs) && (ft === 'all' || c.critique_type === ft))
    .sort((a, b) => ({ critical: 0, warning: 1, note: 2 }[a.severity]) - ({ critical: 0, warning: 1, note: 2 }[b.severity]));
  const selectStyle = { background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-secondary)', borderRadius: '8px', padding: '4px 8px', fontSize: '12px' };

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>Red Team Report</h3>
          <div className="flex gap-3 mt-1">
            <span className="text-xs font-mono" style={{ color: '#fca5a5' }}>{report.critical_count} critical</span>
            <span className="text-xs font-mono" style={{ color: '#fcd34d' }}>{report.warning_count} warning</span>
            <span className="text-xs font-mono" style={{ color: '#93c5fd' }}>{report.note_count} note</span>
          </div>
        </div>
        <div className="flex gap-2">
          <select value={fs} onChange={(e) => setFs(e.target.value as CritiqueSeverity | 'all')} style={selectStyle}>
            <option value="all">All Severity</option><option value="critical">Critical</option><option value="warning">Warning</option><option value="note">Note</option>
          </select>
          <select value={ft} onChange={(e) => setFt(e.target.value as CritiqueType | 'all')} style={selectStyle}>
            <option value="all">All Types</option><option value="devils_advocate">Devil's Advocate</option><option value="hidden_assumption">Assumptions</option><option value="sensitivity">Sensitivity</option><option value="contradiction">Contradictions</option>
          </select>
        </div>
      </div>
      <div className="space-y-2">
        {filtered.map((c, i) => {
          const s = SEV[c.severity];
          return (
            <div key={i} className="p-4 rounded-xl" style={{ background: s.bg, border: `1px solid ${s.border}` }}>
              <div className="flex items-start gap-2">
                <span style={{ color: s.text }}>{s.icon}</span>
                <div className="flex-1">
                  <div className="flex gap-2 items-center mb-1">
                    <span className="text-xs font-bold uppercase" style={{ color: s.text }}>{c.severity}</span>
                    <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: 'rgba(255,255,255,0.05)', color: 'var(--text-muted)' }}>{TYPES[c.critique_type]}</span>
                  </div>
                  <p className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{c.claim_challenged}</p>
                  <p className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>{c.evidence_basis}</p>
                  {c.breakpoint_info && <p className="text-xs mt-1 font-mono p-2 rounded" style={{ background: 'rgba(0,0,0,0.2)', color: 'var(--text-muted)' }}>{c.breakpoint_info}</p>}
                  {c.suggested_resolution && <p className="text-xs mt-1 italic" style={{ color: 'var(--text-muted)' }}>Fix: {c.suggested_resolution}</p>}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
