import { api } from '@/lib/api';

export function ExportBar({ projectId }: { projectId: string }) {
  return (
    <button onClick={() => window.open(api.exportPptx(projectId), '_blank')}
      className="text-sm px-3 py-1.5 rounded-lg transition-colors"
      style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)' }}>
      Export PPTX
    </button>
  );
}
