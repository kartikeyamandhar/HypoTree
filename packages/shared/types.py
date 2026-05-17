"""Shared Pydantic models used across agents and API."""
from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class QuestionType(str, Enum):
    GROWTH_MARKET_ENTRY = "growth_market_entry"
    COST_OPTIMIZATION = "cost_optimization"
    MA_RATIONALE = "ma_rationale"
    PRICING_STRATEGY = "pricing_strategy"
    COMPETITIVE_RESPONSE = "competitive_response"
    DIGITAL_TRANSFORMATION = "digital_transformation"
    UNKNOWN = "unknown"


class Framework(str, Enum):
    THREE_CS_MARKET_ATTRACTIVENESS = "3cs_market_attractiveness"
    VALUE_CHAIN_DECOMPOSITION = "value_chain_decomposition"
    SYNERGY_TREE_STANDALONE = "synergy_tree_standalone"
    VALUE_BASED_PRICING = "value_based_pricing"
    GAME_THEORY_PORTERS = "game_theory_porters"
    CAPABILITY_MATURITY_ROI = "capability_maturity_roi"


QUESTION_TYPE_TO_FRAMEWORK: dict[QuestionType, Framework] = {
    QuestionType.GROWTH_MARKET_ENTRY: Framework.THREE_CS_MARKET_ATTRACTIVENESS,
    QuestionType.COST_OPTIMIZATION: Framework.VALUE_CHAIN_DECOMPOSITION,
    QuestionType.MA_RATIONALE: Framework.SYNERGY_TREE_STANDALONE,
    QuestionType.PRICING_STRATEGY: Framework.VALUE_BASED_PRICING,
    QuestionType.COMPETITIVE_RESPONSE: Framework.GAME_THEORY_PORTERS,
    QuestionType.DIGITAL_TRANSFORMATION: Framework.CAPABILITY_MATURITY_ROI,
}


class TestabilityClass(str, Enum):
    QUANTITATIVE = "quantitative"
    QUALITATIVE = "qualitative"
    ASSUMPTION = "assumption"
    ALREADY_ANSWERED = "already_answered"


class AnalysisType(str, Enum):
    REGRESSION = "regression"
    BENCHMARKING = "benchmarking"
    COHORT_ANALYSIS = "cohort_analysis"
    SCENARIO_MODELING = "scenario_modeling"
    BREAK_EVEN = "break_even"
    MARKET_SIZING = "market_sizing"
    COMPETITIVE_ANALYSIS = "competitive_analysis"
    FINANCIAL_MODELING = "financial_modeling"
    SURVEY_ANALYSIS = "survey_analysis"
    EXPERT_INTERVIEWS = "expert_interviews"
    CASE_STUDY = "case_study"
    DATA_ANALYSIS = "data_analysis"
    COST_ANALYSIS = "cost_analysis"
    SENSITIVITY_ANALYSIS = "sensitivity_analysis"


class ConfidenceLevel(str, Enum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class CritiqueSeverity(str, Enum):
    CRITICAL = "critical"
    WARNING = "warning"
    NOTE = "note"


class CritiqueType(str, Enum):
    DEVILS_ADVOCATE = "devils_advocate"
    HIDDEN_ASSUMPTION = "hidden_assumption"
    SENSITIVITY = "sensitivity"
    CONTRADICTION = "contradiction"


class HypothesisState(str, Enum):
    TRUE = "true"
    FALSE = "false"
    UNCERTAIN = "uncertain"


class Critique(BaseModel):
    critique_type: CritiqueType
    severity: CritiqueSeverity
    target_node_id: str
    target_node_statement: str = ""
    related_node_id: Optional[str] = None
    related_node_statement: str = ""
    claim_challenged: str
    evidence_basis: str
    suggested_resolution: str = ""
    breakpoint_info: Optional[str] = None


class StressTestReport(BaseModel):
    critiques: list[Critique] = Field(default_factory=list)
    summary: str = ""
    critical_count: int = 0
    warning_count: int = 0
    note_count: int = 0

    def compute_counts(self) -> None:
        self.critical_count = len([c for c in self.critiques if c.severity == CritiqueSeverity.CRITICAL])
        self.warning_count = len([c for c in self.critiques if c.severity == CritiqueSeverity.WARNING])
        self.note_count = len([c for c in self.critiques if c.severity == CritiqueSeverity.NOTE])


class CausalEdge(BaseModel):
    source_id: str
    target_id: str
    relationship: str = ""
    strength: float = 1.0


class CausalDAG(BaseModel):
    edges: list[CausalEdge] = Field(default_factory=list)
    node_states: dict[str, HypothesisState] = Field(default_factory=dict)
    node_probabilities: dict[str, float] = Field(default_factory=dict)


class ScenarioConfig(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4())[:8])
    name: str = ""
    node_states: dict[str, HypothesisState] = Field(default_factory=dict)
    node_probabilities: dict[str, float] = Field(default_factory=dict)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class DataPoint(BaseModel):
    metric: str
    value: str
    source: str
    source_url: str = ""
    confidence: ConfidenceLevel = ConfidenceLevel.MEDIUM
    recency: str = ""
    notes: str = ""


class DataGap(BaseModel):
    description: str
    why_needed: str
    suggested_alternative: str = ""


class DataCard(BaseModel):
    hypothesis_id: str
    data_points: list[DataPoint] = Field(default_factory=list)
    gaps: list[DataGap] = Field(default_factory=list)
    summary: str = ""
    retrieval_status: str = "pending"


class TestabilityResult(BaseModel):
    classification: TestabilityClass
    confidence: float = 0.0
    rationale: str = ""
    impact_score: int = Field(default=3, ge=1, le=5)
    testability_score: int = Field(default=2, ge=1, le=3)
    data_availability_score: int = Field(default=2, ge=1, le=3)

    @property
    def priority_score(self) -> float:
        return self.impact_score * self.testability_score * self.data_availability_score


class AnalysisDesign(BaseModel):
    analysis_type: AnalysisType
    methodology: str = ""
    data_sources: list[str] = Field(default_factory=list)
    output_format: str = ""
    loe_hours: float = 0.0
    rationale: str = ""


class HypothesisNode(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4())[:8])
    statement: str
    parent_id: Optional[str] = None
    children: list[HypothesisNode] = Field(default_factory=list)
    depth: int = 0
    what_must_be_true: Optional[str] = None
    evidence_needed: Optional[str] = None
    is_leaf: bool = False
    testability: Optional[TestabilityResult] = None
    analysis: Optional[AnalysisDesign] = None
    data_card: Optional[DataCard] = None
    stress_test_severity: Optional[CritiqueSeverity] = None

    model_config = {"arbitrary_types_allowed": True}


class MECEValidationResult(BaseModel):
    is_valid: bool
    overlaps: list[str] = Field(default_factory=list)
    gaps: list[str] = Field(default_factory=list)
    suggestions: list[str] = Field(default_factory=list)


class ClassificationResult(BaseModel):
    question_type: QuestionType
    framework: Framework
    confidence: float
    rationale: str


class HypothesisTree(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    root: HypothesisNode
    classification: ClassificationResult
    industry: str
    company: str
    question: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    metadata: dict = Field(default_factory=dict)
    stress_test_report: Optional[StressTestReport] = None
    causal_dag: Optional[CausalDAG] = None
    scenarios: list[ScenarioConfig] = Field(default_factory=list)
    workplan: Optional[dict] = None

    def get_all_nodes(self) -> list[HypothesisNode]:
        nodes: list[HypothesisNode] = []
        def _walk(node: HypothesisNode) -> None:
            nodes.append(node)
            for child in node.children:
                _walk(child)
        _walk(self.root)
        return nodes

    def get_leaf_nodes(self) -> list[HypothesisNode]:
        return [n for n in self.get_all_nodes() if n.is_leaf]


class ProjectCreate(BaseModel):
    industry: str
    company: str
    question: str


class ProjectResponse(BaseModel):
    id: str
    industry: str
    company: str
    question: str
    status: str
    tree: Optional[HypothesisTree] = None
    created_at: datetime
