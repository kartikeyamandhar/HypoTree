import { useState, useEffect } from 'react';

interface PastCase {
  id: string;
  industry: string;
  company: string;
  question: string;
  question_type: string;
  framework: string;
  node_count: number;
  leaf_count: number;
  created_at: string;
}

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

export function PastCases() {
  const [cases, setCases] = useState<PastCase[]>([]);

  useEffect(() => {
    fetch(`${API_URL}/api/memory/cases`)
      .then((r) => r.json())
      .then(setCases)
      .catch(() => {});
  }, []);

  if (cases.length === 0) return null;

  return (
    <div className="mt-12">
      <h3 className="text-sm font-mono mb-3" style={{ color: 'var(--text-muted)' }}>PAST ANALYSES</h3>
      <div className="space-y-2">
        {cases.map((c) => (
          <div key={c.id} className="p-3 rounded-xl transition-colors cursor-default"
            style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
            <p className="text-sm" style={{ color: 'var(--text-primary)' }}>{c.question}</p>
            <div className="flex gap-4 mt-1.5 text-xs" style={{ color: 'var(--text-muted)' }}>
              <span>{c.industry}</span>
              <span>{c.company}</span>
              <span>{c.node_count} nodes</span>
              <span>{c.question_type.replace(/_/g, ' ')}</span>
              <span>{new Date(c.created_at).toLocaleDateString()}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
