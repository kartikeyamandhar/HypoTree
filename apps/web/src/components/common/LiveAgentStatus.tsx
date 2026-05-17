import { useState, useEffect, useRef } from 'react';

interface LogEntry { ts: number; phase: string; agent: string; message: string; level: string; }

const PHASE_META: Record<string, { label: string; color: string; description: string }> = {
  P1: { label: 'Building Hypothesis Tree', color: '#6366f1', description: 'Decomposing the strategic question into a structured MECE tree' },
  P2: { label: 'Classifying and Designing', color: '#3b82f6', description: 'Determining how each hypothesis can be tested and what analysis to run' },
  P3: { label: 'Gathering Real Data', color: '#22c55e', description: 'Pulling financial data from Yahoo Finance, SEC filings, and public sources' },
  P4: { label: 'Stress-Testing', color: '#ef4444', description: 'An adversarial agent is challenging assumptions and finding contradictions' },
  P5: { label: 'Mapping Dependencies', color: '#a855f7', description: 'Identifying which hypotheses depend on each other for scenario modeling' },
  P6: { label: 'Building Workplan', color: '#f59e0b', description: 'Grouping analyses into workstreams with timelines and resource assignments' },
  P8: { label: 'Saving to Memory', color: '#14b8a6', description: 'Storing this analysis for institutional learning on future questions' },
  done: { label: 'Complete', color: '#22c55e', description: 'All phases finished' },
};

const DEFAULT_META = { label: 'Processing', color: '#6366f1', description: 'Working...' };

interface Props { projectId: string | null; onComplete: () => void; }

export function LiveAgentStatus({ projectId, onComplete }: Props) {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [currentPhase, setCurrentPhase] = useState('P1');
  const [startTime] = useState(Date.now());
  const [elapsed, setElapsed] = useState(0);
  const feedRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const t = setInterval(() => setElapsed(Math.floor((Date.now() - startTime) / 1000)), 1000);
    return () => clearInterval(t);
  }, [startTime]);

  useEffect(() => {
    if (!projectId) return;
    const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    const es = new EventSource(`${apiUrl}/api/projects/${projectId}/stream`);
    es.onmessage = (event) => {
      try {
        const entry: LogEntry = JSON.parse(event.data);
        setLogs((prev) => [...prev, entry]);
        if (entry.phase && entry.phase !== 'done' && entry.phase !== '') setCurrentPhase(entry.phase);
        if (entry.phase === 'done') { es.close(); setTimeout(onComplete, 1500); }
      } catch (_e) { /* keepalive */ }
    };
    es.onerror = () => { setTimeout(onComplete, 3000); };
    return () => es.close();
  }, [projectId, onComplete]);

  useEffect(() => {
    feedRef.current?.scrollTo({ top: feedRef.current.scrollHeight, behavior: 'smooth' });
  }, [logs]);

  const formatTime = (s: number) => `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, '0')}`;
  const meta = PHASE_META[currentPhase] ?? DEFAULT_META;
  const phases = ['P1', 'P2', 'P3', 'P4', 'P5', 'P6'];
  const completedPhases = new Set(logs.filter(l => l.message.toLowerCase().includes('complete')).map(l => l.phase));
  const visibleLogs = logs.filter(l => !l.message.includes('tokens_in=') && l.message.length > 0 && l.phase !== '');

  return (
    <div className="max-w-3xl mx-auto py-12">
      <div className="text-center mb-8">
        <div className="inline-flex items-center gap-3 px-5 py-2.5 rounded-2xl mb-4"
          style={{ background: meta.color + '15', border: `1px solid ${meta.color}33` }}>
          <div className="w-2.5 h-2.5 rounded-full animate-pulse" style={{ background: meta.color }} />
          <span className="text-sm font-semibold" style={{ color: meta.color }}>{meta.label}</span>
          <span className="text-xs font-mono px-2 py-0.5 rounded-full" style={{ background: 'var(--bg-primary)', color: 'var(--text-muted)' }}>{formatTime(elapsed)}</span>
        </div>
        <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>{meta.description}</p>
      </div>

      <div className="flex justify-center gap-3 mb-8">
        {phases.map((p) => {
          const pm = PHASE_META[p] ?? DEFAULT_META;
          const done = completedPhases.has(p) || phases.indexOf(p) < phases.indexOf(currentPhase);
          const active = p === currentPhase;
          return (
            <div key={p} className="flex flex-col items-center gap-1.5">
              <div className="w-9 h-9 rounded-lg flex items-center justify-center text-xs font-mono font-bold transition-all duration-500"
                style={{
                  background: done ? pm.color + '22' : active ? pm.color + '15' : 'var(--bg-card)',
                  border: `2px solid ${active ? pm.color : done ? pm.color + '44' : 'var(--border-subtle)'}`,
                  color: done ? pm.color : active ? pm.color : 'var(--text-muted)',
                }}>
                {done ? '\u2713' : p.replace('P', '')}
              </div>
            </div>
          );
        })}
      </div>

      <div className="rounded-2xl overflow-hidden" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
        <div className="px-5 py-3 flex items-center justify-between" style={{ borderBottom: '1px solid var(--border-subtle)' }}>
          <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>Activity</span>
          <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>{visibleLogs.length} events</span>
        </div>
        <div ref={feedRef} className="px-5 py-3 overflow-y-auto" style={{ maxHeight: '50vh', minHeight: '250px' }}>
          {visibleLogs.map((entry, i) => {
            const pm = PHASE_META[entry.phase] ?? DEFAULT_META;
            const isWarning = entry.level === 'warning';
            const isRecent = i >= visibleLogs.length - 3;
            return (
              <div key={i} className="flex gap-3 py-2.5 transition-opacity duration-500" style={{ opacity: isRecent ? 1 : 0.5 }}>
                <div className="flex flex-col items-center flex-shrink-0" style={{ width: '20px' }}>
                  <div className="w-2 h-2 rounded-full flex-shrink-0 mt-1" style={{ background: pm.color, boxShadow: isRecent ? `0 0 6px ${pm.color}44` : 'none' }} />
                  {i < visibleLogs.length - 1 && <div className="w-px flex-1 mt-1" style={{ background: 'var(--border-subtle)' }} />}
                </div>
                <div className="flex-1 min-w-0 pb-1">
                  <span className="text-xs font-semibold" style={{ color: pm.color }}>{entry.agent}</span>
                  <p className="text-sm mt-0.5 leading-relaxed" style={{ color: isWarning ? '#fbbf24' : 'var(--text-secondary)' }}>{entry.message}</p>
                </div>
              </div>
            );
          })}
          <div className="flex gap-3 py-2">
            <div className="flex flex-col items-center" style={{ width: '20px' }}>
              <div className="w-2 h-2 rounded-full animate-pulse mt-1" style={{ background: meta.color }} />
            </div>
            <span className="text-sm animate-pulse" style={{ color: 'var(--text-muted)' }}>Working...</span>
          </div>
        </div>
      </div>
    </div>
  );
}
