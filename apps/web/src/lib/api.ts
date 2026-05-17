import type { Project, ProjectCreate } from '@/types/project';

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, { headers: { 'Content-Type': 'application/json' }, ...options });
  if (!res.ok) { const body = await res.json().catch(() => ({ detail: res.statusText })); throw new Error(body.detail || `HTTP ${res.status}`); }
  return res.json() as Promise<T>;
}

export const api = {
  createProject: (data: ProjectCreate) => request<Project>('/api/projects', { method: 'POST', body: JSON.stringify(data) }),
  generateTree: (projectId: string) => request<Project>(`/api/projects/${projectId}/generate`, { method: 'POST' }),
  getProject: (projectId: string) => request<Project>(`/api/projects/${projectId}`),
  listProjects: () => request<Project[]>('/api/projects'),
  toggleNode: (projectId: string, nodeId: string, state: string) =>
    request<{ node_states: Record<string, string>; node_probabilities: Record<string, number> }>(`/api/projects/${projectId}/dag/toggle`, { method: 'POST', body: JSON.stringify({ node_id: nodeId, state }) }),
  negotiateWorkplan: (projectId: string, message: string) =>
    request<unknown>(`/api/projects/${projectId}/workplan/negotiate`, { method: 'POST', body: JSON.stringify({ message }) }),
  submitFeedback: (projectId: string, nodeId: string, outcome: string, notes: string = '') =>
    request<unknown>(`/api/projects/${projectId}/feedback`, { method: 'POST', body: JSON.stringify({ node_id: nodeId, outcome, notes }) }),
  submitEvaluation: (projectId: string, data: { correct: number; incorrect: number; irrelevant: number; missing: number }) =>
    request<unknown>(`/api/projects/${projectId}/evaluate`, { method: 'POST', body: JSON.stringify(data) }),
  getCalibration: () => request<unknown>('/api/evaluation/calibration'),
  exportPptx: (projectId: string) => `${API_URL}/api/projects/${projectId}/export/pptx`,
};
