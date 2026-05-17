import { useState } from 'react';
import { api } from '@/lib/api';
import type { Workplan, Workstream } from '@/types/hypothesis';

const RES_COLORS: Record<string, string> = { analyst: '#3b82f6', manager: '#f59e0b', partner: '#a855f7' };

export function WorkplanView({ workplan: initial, projectId }: { workplan: Workplan; projectId: string }) {
  const [wp, setWp] = useState<Workplan>(initial);
  const [msg, setMsg] = useState('');
  const [negotiating, setNegotiating] = useState(false);

  const handleNegotiate = async () => {
    if (!msg.trim()) return;
    setNegotiating(true);
    try {
      const result = await api.negotiateWorkplan(projectId, msg.trim());
      setWp(result as Workplan);
      setMsg('');
    } catch (e) {
      console.error(e);
    } finally {
      setNegotiating(false);
    }
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>Workplan</h3>
          <p className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>{wp.workstreams.length} workstreams &middot; {wp.total_loe.toFixed(0)}h &middot; {wp.estimated_weeks} weeks</p>
        </div>
      </div>

      {wp.summary && <p className="text-sm mb-4 p-3 rounded-lg" style={{ background: 'var(--bg-card)', color: 'var(--text-secondary)' }}>{wp.summary}</p>}

      <div className="space-y-3 mb-6">
        {wp.workstreams.map((ws: Workstream) => (
          <div key={ws.id} className="rounded-xl overflow-hidden" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
            <div className="flex items-center justify-between p-3" style={{ borderBottom: '1px solid var(--border-subtle)' }}>
              <div className="flex items-center gap-3">
                <span className="text-xs font-mono px-2 py-0.5 rounded" style={{ background: 'var(--accent-indigo)', color: 'white' }}>{ws.id}</span>
                <span className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>{ws.name}</span>
              </div>
              <div className="flex items-center gap-3">
                {ws.depends_on.length > 0 && (
                  <span className="text-xs" style={{ color: 'var(--text-muted)' }}>after {ws.depends_on.join(', ')}</span>
                )}
                <span className="text-xs font-mono" style={{ color: 'var(--accent-amber)' }}>{ws.total_loe}h</span>
              </div>
            </div>
            <div className="p-2 space-y-1">
              {ws.items.map((item, i) => (
                <div key={i} className="flex items-center gap-3 py-1.5 px-2 rounded" style={{ background: 'var(--bg-secondary)' }}>
                  <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: RES_COLORS[item.resource_type] ?? '#6b7280' }} />
                  <p className="text-xs flex-1 truncate" style={{ color: 'var(--text-secondary)' }}>{item.hypothesis_statement || item.hypothesis_id}</p>
                  <span className="text-xs" style={{ color: 'var(--text-muted)' }}>{item.analysis_type.replace(/_/g, ' ')}</span>
                  <span className="text-xs font-mono w-8 text-right" style={{ color: 'var(--text-muted)' }}>{item.loe_hours}h</span>
                  <span className="text-xs capitalize" style={{ color: RES_COLORS[item.resource_type] }}>{item.resource_type}</span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      <div className="flex gap-4 mb-6">
        {Object.entries(RES_COLORS).map(([role, color]) => (
          <div key={role} className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full" style={{ background: color }} />
            <span className="text-xs capitalize" style={{ color: 'var(--text-muted)' }}>{role}</span>
          </div>
        ))}
      </div>

      <div className="p-4 rounded-xl" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
        <p className="text-xs font-mono mb-2" style={{ color: 'var(--text-muted)' }}>NEGOTIATE WORKPLAN</p>
        <div className="flex gap-2">
          <input type="text" value={msg} onChange={(e) => setMsg(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleNegotiate()}
            placeholder='e.g., "We only have 3 weeks, reprioritize"'
            className="flex-1 px-3 py-2 rounded-lg text-sm outline-none"
            style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)' }}
            disabled={negotiating} />
          <button onClick={handleNegotiate} disabled={negotiating || !msg.trim()}
            className="px-4 py-2 rounded-lg text-sm font-medium transition-colors"
            style={{ background: msg.trim() ? 'var(--accent-indigo)' : 'var(--bg-secondary)', color: msg.trim() ? 'white' : 'var(--text-muted)' }}>
            {negotiating ? '...' : 'Send'}
          </button>
        </div>
      </div>
    </div>
  );
}
