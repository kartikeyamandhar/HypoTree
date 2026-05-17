import type { TestabilityClass } from '@/types/hypothesis';

const COLORS: Record<TestabilityClass, { bg: string; text: string; label: string }> = {
  quantitative: { bg: '#132b1a', text: '#4ade80', label: 'Quant' },
  qualitative: { bg: '#1a2332', text: '#60a5fa', label: 'Qual' },
  assumption: { bg: '#2d2510', text: '#fbbf24', label: 'Assumption' },
  already_answered: { bg: '#221a33', text: '#c084fc', label: 'Answered' },
};

export function TestabilityBadge({ classification }: { classification: TestabilityClass; className?: string }) {
  const c = COLORS[classification] ?? { bg: '#1f2937', text: '#9ca3af', label: classification };
  return <span className="text-xs px-1.5 py-0.5 rounded font-medium" style={{ background: c.bg, color: c.text, fontSize: '10px' }}>{c.label}</span>;
}
