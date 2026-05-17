import { api } from '@/lib/api';

interface Props {
  projectId: string;
}

export function ExportBar({ projectId }: Props) {
  const handleExport = () => {
    window.open(api.exportPptx(projectId), '_blank');
  };

  return (
    <div className="flex items-center gap-3">
      <button onClick={handleExport}
        className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors"
        style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)' }}>
        <span>{'\u{1F4E5}'}</span> Export PowerPoint
      </button>
    </div>
  );
}
