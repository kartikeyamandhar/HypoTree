import { useState } from 'react';
import type { ProjectCreate } from '@/types/project';
import { PastCases } from '@/components/memory/PastCases';

interface Props {
  onSubmit: (data: ProjectCreate) => void;
  loading: boolean;
}

export function QuestionInput({ onSubmit, loading }: Props) {
  const [industry, setIndustry] = useState('');
  const [company, setCompany] = useState('');
  const [question, setQuestion] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!industry.trim() || !company.trim() || !question.trim()) return;
    onSubmit({ industry: industry.trim(), company: company.trim(), question: question.trim() });
  };

  const ready = industry.trim() && company.trim() && question.trim() && !loading;

  return (
    <div className="max-w-xl mx-auto pt-16">
      <div className="text-center mb-10">
        <h2 className="text-3xl font-bold mb-2" style={{ color: 'var(--text-primary)' }}>
          Strategic Hypothesis Engine
        </h2>
        <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
          MECE hypothesis tree with testability classification, real data, adversarial stress-testing, and structured workplan.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>INDUSTRY</label>
            <input type="text" value={industry} onChange={(e) => setIndustry(e.target.value)} placeholder="e.g., Semiconductor"
              className="w-full px-3 py-2.5 rounded-lg text-sm outline-none" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)' }} disabled={loading} />
          </div>
          <div>
            <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>COMPANY</label>
            <input type="text" value={company} onChange={(e) => setCompany(e.target.value)} placeholder="e.g., Skyworks Solutions"
              className="w-full px-3 py-2.5 rounded-lg text-sm outline-none" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)' }} disabled={loading} />
          </div>
        </div>
        <div>
          <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>STRATEGIC QUESTION</label>
          <textarea value={question} onChange={(e) => setQuestion(e.target.value)} placeholder="e.g., Should Skyworks and Qorvo merge?" rows={3}
            className="w-full px-3 py-2.5 rounded-lg text-sm outline-none resize-none" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)' }} disabled={loading} />
        </div>
        <button type="submit" disabled={!ready} className="w-full py-3 rounded-lg text-sm font-semibold transition-all duration-200"
          style={{ background: ready ? 'var(--accent-indigo)' : 'var(--bg-card)', color: ready ? 'white' : 'var(--text-muted)', cursor: ready ? 'pointer' : 'not-allowed' }}>
          Generate Hypothesis Tree
        </button>
      </form>

      <PastCases />
    </div>
  );
}
