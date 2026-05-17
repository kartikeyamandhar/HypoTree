import type { HypothesisTree } from './hypothesis';

export interface Project {
  id: string;
  industry: string;
  company: string;
  question: string;
  status: 'created' | 'generating' | 'complete' | 'error';
  tree: HypothesisTree | null;
  created_at: string;
}

export interface ProjectCreate {
  industry: string;
  company: string;
  question: string;
}
