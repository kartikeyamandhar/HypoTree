import { useState, useCallback } from 'react';
import { QuestionInput } from '@/components/forms/QuestionInput';
import { HypothesisTreeView } from '@/components/tree/HypothesisTree';
import { AnalysisPlanTable } from '@/components/analysis/AnalysisPlanTable';
import { StressTestReportView } from '@/components/stress-test/StressTestReport';
import { ScenarioDAGView } from '@/components/dag/ScenarioDAGView';
import { WorkplanView } from '@/components/workplan/WorkplanView';
import { ExportBar } from '@/components/export/ExportBar';
import { LiveAgentStatus } from '@/components/common/LiveAgentStatus';
import { ErrorBoundary } from '@/components/common/ErrorBoundary';
import { api } from '@/lib/api';
import type { Project, ProjectCreate } from '@/types/project';

type ViewMode = 'tree' | 'table' | 'stress' | 'dag' | 'workplan';

const TAB_CONFIG: { key: ViewMode; label: string }[] = [
  { key: 'tree', label: 'Hypothesis Tree' },
  { key: 'table', label: 'Analysis Plan' },
  { key: 'stress', label: 'Red Team' },
  { key: 'dag', label: 'Scenarios' },
  { key: 'workplan', label: 'Workplan' },
];

function App() {
  const [project, setProject] = useState<Project | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [viewMode, setViewMode] = useState<ViewMode>('tree');
  const [projectId, setProjectId] = useState<string | null>(null);

  const handleSubmit = async (data: ProjectCreate) => {
    setLoading(true); setError(null);
    try {
      const created = await api.createProject(data);
      setProjectId(created.id);
      await api.generateTree(created.id);
    } catch (e) { setError(e instanceof Error ? e.message : 'Unknown error'); setLoading(false); }
  };

  const handleStreamComplete = useCallback(async () => {
    if (!projectId) return;
    try {
      for (let i = 0; i < 15; i++) {
        const result = await api.getProject(projectId);
        if (result.tree) { setProject(result); break; }
        if (result.status === 'error') { setError('Generation failed'); break; }
        await new Promise((r) => setTimeout(r, 2000));
      }
    } catch (e) { setError(e instanceof Error ? e.message : 'Failed to fetch'); }
    finally { setLoading(false); }
  }, [projectId]);

  const handleReset = () => { setProject(null); setError(null); setViewMode('tree'); setProjectId(null); setLoading(false); };

  const visibleTabs = TAB_CONFIG.filter((t) => {
    if (!project?.tree) return false;
    if (t.key === 'stress') return !!project.tree.stress_test_report;
    if (t.key === 'dag') return !!project.tree.causal_dag;
    if (t.key === 'workplan') return !!project.tree.workplan;
    return true;
  });

  return (
    <ErrorBoundary>
      <div className="min-h-screen" style={{ background: 'var(--bg-primary)' }}>
        <header className="border-b px-6 py-3" style={{ background: 'var(--bg-secondary)', borderColor: 'var(--border-subtle)' }}>
          <div className="flex items-center justify-between max-w-screen-2xl mx-auto">
            <div className="flex items-center gap-3 cursor-pointer" onClick={handleReset}>
              <div className="w-8 h-8 rounded-lg flex items-center justify-center text-sm font-bold" style={{ background: 'var(--accent-indigo)', color: 'white' }}>H</div>
              <span className="text-lg font-bold" style={{ color: 'var(--text-primary)', fontFamily: 'var(--font-mono)' }}>HypoTree</span>
            </div>

            {project?.tree && (
              <nav className="flex items-center gap-0.5 p-1 rounded-xl" style={{ background: 'var(--bg-primary)' }}>
                {visibleTabs.map((tab) => {
                  const active = viewMode === tab.key;
                  const badge = tab.key === 'stress' && project?.tree?.stress_test_report
                    ? project.tree.stress_test_report.critical_count : null;
                  return (
                    <button key={tab.key} onClick={() => setViewMode(tab.key)}
                      className="px-4 py-1.5 text-sm rounded-lg transition-all duration-150"
                      style={{
                        background: active ? 'var(--accent-indigo)' : 'transparent',
                        color: active ? 'white' : 'var(--text-secondary)',
                        fontWeight: active ? 600 : 400,
                      }}>
                      {tab.label}
                      {badge !== null && badge > 0 && (
                        <span className="ml-2 text-xs px-1.5 py-0.5 rounded-full"
                          style={{ background: active ? 'rgba(255,255,255,0.2)' : 'var(--accent-red)', color: 'white' }}>
                          {badge}
                        </span>
                      )}
                    </button>
                  );
                })}
              </nav>
            )}

            <div className="flex items-center gap-3">
              {project && projectId && <ExportBar projectId={projectId} />}
              {(project || loading) && (
                <button onClick={handleReset} className="text-sm px-3 py-1.5 rounded-lg transition-colors"
                  style={{ color: 'var(--text-secondary)', border: '1px solid var(--border-subtle)' }}>
                  New Analysis
                </button>
              )}
            </div>
          </div>
        </header>

        <main className="max-w-screen-2xl mx-auto py-6 px-6">
          {error && (
            <div className="mb-6 p-4 rounded-xl border text-sm"
              style={{ background: '#1c1012', borderColor: 'var(--accent-red)', color: '#fca5a5' }}>
              {error}
            </div>
          )}

          {loading && <LiveAgentStatus projectId={projectId} onComplete={handleStreamComplete} />}
          {!loading && !project && <QuestionInput onSubmit={handleSubmit} loading={loading} />}

          {!loading && project?.tree && (
            <div>
              {/* Context bar */}
              <div className="mb-6 p-4 rounded-xl" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
                <div className="flex items-center gap-8 text-sm" style={{ color: 'var(--text-secondary)' }}>
                  <div>
                    <span className="text-xs block" style={{ color: 'var(--text-muted)' }}>Industry</span>
                    <span style={{ color: 'var(--text-primary)' }}>{project.industry}</span>
                  </div>
                  <div>
                    <span className="text-xs block" style={{ color: 'var(--text-muted)' }}>Company</span>
                    <span style={{ color: 'var(--text-primary)' }}>{project.company}</span>
                  </div>
                  <div>
                    <span className="text-xs block" style={{ color: 'var(--text-muted)' }}>Framework</span>
                    <span style={{ color: 'var(--accent-indigo)' }}>{project.tree.classification.framework.replace(/_/g, ' ')}</span>
                  </div>
                  <div>
                    <span className="text-xs block" style={{ color: 'var(--text-muted)' }}>Confidence</span>
                    <span style={{ color: 'var(--accent-green)' }}>{(project.tree.classification.confidence * 100).toFixed(0)}%</span>
                  </div>
                </div>
                <p className="mt-3 text-sm" style={{ color: 'var(--text-primary)' }}>{project.question}</p>
              </div>

              {viewMode === 'tree' && <HypothesisTreeView root={project.tree.root} projectId={projectId ?? undefined} />}
              {viewMode === 'table' && <AnalysisPlanTable root={project.tree.root} />}
              {viewMode === 'stress' && project.tree.stress_test_report && <StressTestReportView report={project.tree.stress_test_report} />}
              {viewMode === 'dag' && project.tree.causal_dag && <ScenarioDAGView tree={project.tree} projectId={project.id} />}
              {viewMode === 'workplan' && project.tree.workplan && <WorkplanView workplan={project.tree.workplan} projectId={project.id} />}
            </div>
          )}
        </main>
      </div>
    </ErrorBoundary>
  );
}

export default App;
