import type { DataCard as DC } from '@/types/hypothesis';

const CONF = { high: '#22c55e', medium: '#f59e0b', low: '#ef4444' };

export function DataCardView({ card }: { card: DC }) {
  if (!card.data_points.length && !card.gaps.length) return null;
  return (
    <div>
      <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>DATA</span>
      {card.data_points.map((dp, i) => (
        <div key={i} className="mt-2 p-2 rounded" style={{ background: 'var(--bg-secondary)' }}>
          <div className="flex justify-between items-start">
            <p className="text-xs" style={{ color: 'var(--text-secondary)' }}>{dp.metric}</p>
            <span className="w-2 h-2 rounded-full flex-shrink-0 mt-0.5" style={{ background: CONF[dp.confidence] }} />
          </div>
          <p className="text-sm font-semibold font-mono" style={{ color: 'var(--accent-blue)' }}>{dp.value}</p>
          <p className="text-xs" style={{ color: 'var(--text-muted)' }}>{dp.source}</p>
        </div>
      ))}
      {card.gaps.map((g, i) => (
        <div key={i} className="mt-2 p-2 rounded" style={{ background: '#2d2510', border: '1px solid #92400e' }}>
          <p className="text-xs font-medium" style={{ color: '#fbbf24' }}>{g.description}</p>
          <p className="text-xs mt-0.5" style={{ color: '#d97706' }}>{g.suggested_alternative}</p>
        </div>
      ))}
    </div>
  );
}
