export function ConfidenceBadge({ level }: { level: string; className?: string }) {
  const c = level === 'high' ? '#22c55e' : level === 'medium' ? '#f59e0b' : '#ef4444';
  return <span className="w-2 h-2 rounded-full inline-block" style={{ background: c }} />;
}
