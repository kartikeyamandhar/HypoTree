import type { DataGap } from '@/types/hypothesis';
export function GapFlag({ gap }: { gap: DataGap }) {
  return (
    <div className="p-2 rounded text-xs" style={{ background: '#2d2510', border: '1px solid #92400e', color: '#fbbf24' }}>
      {gap.description}
    </div>
  );
}
