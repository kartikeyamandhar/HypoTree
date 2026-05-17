export type QuestionType = 'growth_market_entry' | 'cost_optimization' | 'ma_rationale' | 'pricing_strategy' | 'competitive_response' | 'digital_transformation' | 'unknown';
export type TestabilityClass = 'quantitative' | 'qualitative' | 'assumption' | 'already_answered';
export type AnalysisType = 'regression' | 'benchmarking' | 'cohort_analysis' | 'scenario_modeling' | 'break_even' | 'market_sizing' | 'competitive_analysis' | 'financial_modeling' | 'survey_analysis' | 'expert_interviews' | 'case_study' | 'data_analysis' | 'cost_analysis' | 'sensitivity_analysis';
export type ConfidenceLevel = 'high' | 'medium' | 'low';
export type CritiqueSeverity = 'critical' | 'warning' | 'note';
export type CritiqueType = 'devils_advocate' | 'hidden_assumption' | 'sensitivity' | 'contradiction';
export type HypothesisState = 'true' | 'false' | 'uncertain';

export interface Critique { critique_type: CritiqueType; severity: CritiqueSeverity; target_node_id: string; target_node_statement: string; related_node_id: string | null; related_node_statement: string; claim_challenged: string; evidence_basis: string; suggested_resolution: string; breakpoint_info: string | null; }
export interface StressTestReport { critiques: Critique[]; summary: string; critical_count: number; warning_count: number; note_count: number; }
export interface CausalEdge { source_id: string; target_id: string; relationship: string; strength: number; }
export interface CausalDAG { edges: CausalEdge[]; node_states: Record<string, HypothesisState>; node_probabilities: Record<string, number>; }
export interface ScenarioConfig { id: string; name: string; node_states: Record<string, HypothesisState>; node_probabilities: Record<string, number>; created_at: string; }
export interface DataPoint { metric: string; value: string; source: string; source_url: string; confidence: ConfidenceLevel; recency: string; notes: string; }
export interface DataGap { description: string; why_needed: string; suggested_alternative: string; }
export interface DataCard { hypothesis_id: string; data_points: DataPoint[]; gaps: DataGap[]; summary: string; retrieval_status: string; }
export interface TestabilityResult { classification: TestabilityClass; confidence: number; rationale: string; impact_score: number; testability_score: number; data_availability_score: number; priority_score?: number; }
export interface AnalysisDesign { analysis_type: AnalysisType; methodology: string; data_sources: string[]; output_format: string; loe_hours: number; rationale: string; }
export interface HypothesisNode { id: string; statement: string; parent_id: string | null; children: HypothesisNode[]; depth: number; what_must_be_true: string | null; evidence_needed: string | null; is_leaf: boolean; testability: TestabilityResult | null; analysis: AnalysisDesign | null; data_card: DataCard | null; stress_test_severity: CritiqueSeverity | null; }
export interface ClassificationResult { question_type: QuestionType; framework: string; confidence: number; rationale: string; }

export interface WorkItem { hypothesis_id: string; hypothesis_statement: string; analysis_type: string; loe_hours: number; resource_type: string; }
export interface Workstream { id: string; name: string; description: string; items: WorkItem[]; total_loe: number; sequence_order: number; depends_on: string[]; }
export interface Workplan { workstreams: Workstream[]; total_loe: number; estimated_weeks: number; critical_path: string[]; summary: string; }

export interface HypothesisTree { id: string; root: HypothesisNode; classification: ClassificationResult; industry: string; company: string; question: string; created_at: string; metadata: Record<string, unknown>; stress_test_report: StressTestReport | null; causal_dag: CausalDAG | null; scenarios: ScenarioConfig[]; workplan: Workplan | null; }
