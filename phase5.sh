#!/bin/bash
set -e

# ============================================================
# HypoTree Phase 5 — Causal DAG + Scenario Modeling
# Run from hypotree/ root
# Usage: bash phase5.sh
# ============================================================

echo "=== Phase 5: Causal DAG + Scenario Modeling ==="

# ======================== SHARED TYPES — add DAG + scenario models ========================
cat > packages/shared/types.py << 'PYEOF'
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
PYEOF

# ======================== DAG BUILDER — causal dependency inference ========================
cat > packages/agents/graph/builder.py << 'PYEOF'
"""Causal DAG builder — constructs dependency graph from hypothesis tree."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.shared.types import CausalDAG, CausalEdge, HypothesisNode, HypothesisState

logger = logging.getLogger(__name__)

DAG_INFERENCE_PROMPT = """You are a strategy analyst identifying causal dependencies between hypotheses.

Given these hypotheses from a strategy decomposition tree, identify which hypotheses are PREREQUISITES for others. A dependency means: if hypothesis A is FALSE, hypothesis B cannot be TRUE (or becomes significantly less likely).

Only identify strong, logical dependencies. Do not create dependencies between every pair.

Hypotheses:
{hypotheses_block}

Respond ONLY with valid JSON, no markdown fences:
{{
  "edges": [
    {{
      "source_id": "<prerequisite hypothesis id>",
      "target_id": "<dependent hypothesis id>",
      "relationship": "<one sentence describing the dependency>"
    }}
  ]
}}

If no strong dependencies exist, return: {{"edges": []}}"""


class DAGBuilderAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a causal reasoning expert identifying dependencies between strategic hypotheses."

    def build_dag(self, root: HypothesisNode) -> CausalDAG:
        """Build causal DAG from hypothesis tree."""
        all_nodes = self._collect_all(root)

        # Tree edges (parent-child) are inherent dependencies
        tree_edges: list[CausalEdge] = []
        for node in all_nodes:
            for child in node.children:
                tree_edges.append(CausalEdge(
                    source_id=child.id,
                    target_id=node.id,
                    relationship=f"Child hypothesis supports parent",
                    strength=1.0,
                ))

        # Cross-branch dependencies via LLM inference
        # Use depth-1 and depth-2 nodes for cross-branch detection
        mid_nodes = [n for n in all_nodes if 1 <= n.depth <= 2]
        cross_edges = self._infer_cross_dependencies(mid_nodes)

        all_edges = tree_edges + cross_edges

        # Initialize all nodes as uncertain
        node_states: dict[str, HypothesisState] = {}
        node_probs: dict[str, float] = {}
        for node in all_nodes:
            node_states[node.id] = HypothesisState.UNCERTAIN
            node_probs[node.id] = 0.5

        dag = CausalDAG(
            edges=all_edges,
            node_states=node_states,
            node_probabilities=node_probs,
        )

        logger.info("DAG built: %d tree edges, %d cross edges, %d total nodes",
            len(tree_edges), len(cross_edges), len(all_nodes))
        return dag

    def _infer_cross_dependencies(self, nodes: list[HypothesisNode]) -> list[CausalEdge]:
        """Use LLM to identify cross-branch dependencies."""
        if len(nodes) < 2:
            return []

        hypotheses_block = "\n".join(
            f"- [{n.id}] (depth {n.depth}) {n.statement}" for n in nodes
        )

        prompt = DAG_INFERENCE_PROMPT.format(hypotheses_block=hypotheses_block)

        try:
            raw = self.call_llm(prompt)
            data = json.loads(raw)
        except Exception as e:
            logger.warning("Cross-dependency inference failed: %s", str(e))
            return []

        edges = []
        valid_ids = {n.id for n in nodes}
        for edge_data in data.get("edges", []):
            src = edge_data.get("source_id", "")
            tgt = edge_data.get("target_id", "")
            if src in valid_ids and tgt in valid_ids and src != tgt:
                edges.append(CausalEdge(
                    source_id=src,
                    target_id=tgt,
                    relationship=edge_data.get("relationship", ""),
                    strength=0.8,
                ))

        logger.info("Inferred %d cross-branch dependencies", len(edges))
        return edges

    @staticmethod
    def _collect_all(node: HypothesisNode) -> list[HypothesisNode]:
        result = [node]
        for child in node.children:
            result.extend(DAGBuilderAgent._collect_all(child))
        return result
PYEOF

# ======================== DAG STATE PROPAGATION ========================
cat > packages/agents/graph/state.py << 'PYEOF'
"""Belief propagation on causal DAG."""
from __future__ import annotations

from packages.shared.types import CausalDAG, CausalEdge, HypothesisState


def propagate_states(dag: CausalDAG, toggled_id: str, new_state: HypothesisState) -> CausalDAG:
    """Propagate a state change through the DAG. Returns updated DAG."""
    dag.node_states[toggled_id] = new_state

    # Set probability based on state
    if new_state == HypothesisState.TRUE:
        dag.node_probabilities[toggled_id] = 0.95
    elif new_state == HypothesisState.FALSE:
        dag.node_probabilities[toggled_id] = 0.05
    else:
        dag.node_probabilities[toggled_id] = 0.5

    # Build adjacency: for each target, find all sources
    deps: dict[str, list[CausalEdge]] = {}
    for edge in dag.edges:
        if edge.target_id not in deps:
            deps[edge.target_id] = []
        deps[edge.target_id].append(edge)

    # Topological propagation (simplified)
    visited = {toggled_id}
    queue = [toggled_id]

    # Find all nodes that depend on the toggled node (downstream)
    downstream: dict[str, list[str]] = {}
    for edge in dag.edges:
        if edge.source_id not in downstream:
            downstream[edge.source_id] = []
        downstream[edge.source_id].append(edge.target_id)

    while queue:
        current = queue.pop(0)
        for target_id in downstream.get(current, []):
            if target_id in visited:
                continue
            visited.add(target_id)

            # Compute probability from all incoming edges
            incoming = deps.get(target_id, [])
            if incoming:
                # Product of source probabilities (AND logic: all prerequisites needed)
                combined = 1.0
                for edge in incoming:
                    src_prob = dag.node_probabilities.get(edge.source_id, 0.5)
                    combined *= src_prob * edge.strength
                dag.node_probabilities[target_id] = round(min(combined, 0.99), 3)

                # Update state based on probability
                if dag.node_probabilities[target_id] >= 0.7:
                    dag.node_states[target_id] = HypothesisState.TRUE
                elif dag.node_probabilities[target_id] <= 0.3:
                    dag.node_states[target_id] = HypothesisState.FALSE
                else:
                    dag.node_states[target_id] = HypothesisState.UNCERTAIN

            queue.append(target_id)

    return dag


def create_scenario_snapshot(dag: CausalDAG) -> tuple[dict[str, HypothesisState], dict[str, float]]:
    """Capture current DAG state as a scenario snapshot."""
    return dict(dag.node_states), dict(dag.node_probabilities)
PYEOF

# ======================== UPDATE ORCHESTRATOR — add Phase 5 ========================
cat > packages/agents/orchestrator/agent.py << 'PYEOF'
"""Orchestrator agent — routes tasks, classifies questions, manages tree generation."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.decomposer.agent import DecomposerAgent
from packages.agents.mece_validator.agent import MECEValidatorAgent
from packages.agents.testability_classifier.agent import TestabilityClassifierAgent
from packages.agents.analysis_designer.agent import AnalysisDesignerAgent
from packages.agents.data_retrieval.agent import DataRetrievalAgent
from packages.agents.red_team.agent import RedTeamAgent
from packages.agents.graph.builder import DAGBuilderAgent
from packages.agents.orchestrator.prompts import CLASSIFICATION_PROMPT, ROOT_HYPOTHESIS_PROMPT
from packages.shared.constants import MECE_MAX_RETRIES, ORCHESTRATOR_MODEL, TARGET_TREE_DEPTH
from packages.shared.types import (
    ClassificationResult, Framework, HypothesisNode, HypothesisTree,
    QuestionType, TestabilityClass,
)

logger = logging.getLogger(__name__)


class OrchestratorAgent(BaseAgent):
    def __init__(self) -> None:
        super().__init__(model=ORCHESTRATOR_MODEL)
        self.decomposer = DecomposerAgent()
        self.mece_validator = MECEValidatorAgent()
        self.testability_classifier = TestabilityClassifierAgent()
        self.analysis_designer = AnalysisDesignerAgent()
        self.data_retrieval = DataRetrievalAgent()
        self.red_team = RedTeamAgent()
        self.dag_builder = DAGBuilderAgent()

    def get_system_prompt(self) -> str:
        return "You are a strategy consulting orchestrator."

    def classify_question(self, industry, company, question):
        prompt = CLASSIFICATION_PROMPT.format(industry=industry, company=company, question=question)
        raw = self.call_llm(prompt)
        data = json.loads(raw)
        return ClassificationResult(
            question_type=QuestionType(data["question_type"]),
            framework=Framework(data["framework"]),
            confidence=data["confidence"], rationale=data["rationale"])

    def generate_root_and_branches(self, industry, company, question, classification):
        prompt = ROOT_HYPOTHESIS_PROMPT.format(
            industry=industry, company=company, question=question,
            question_type=classification.question_type.value,
            framework=classification.framework.value)
        raw = self.call_llm(prompt)
        data = json.loads(raw)
        root = HypothesisNode(
            statement=data["root"]["statement"],
            what_must_be_true=data["root"].get("what_must_be_true"),
            evidence_needed=data["root"].get("evidence_needed"), depth=0)
        for cd in data["children"]:
            child = HypothesisNode(
                statement=cd["statement"], parent_id=root.id,
                what_must_be_true=cd.get("what_must_be_true"),
                evidence_needed=cd.get("evidence_needed"), depth=1)
            root.children.append(child)
        return root

    def _decompose_with_validation(self, node, industry, company, question):
        children = self.decomposer.decompose(parent=node, industry=industry, company=company, question=question)
        best_children, best_score = children, 999
        for attempt in range(MECE_MAX_RETRIES):
            validation = self.mece_validator.validate(parent=node, children=children)
            score = len(validation.overlaps) + len(validation.gaps)
            if score < best_score: best_score, best_children = score, children
            if validation.is_valid:
                logger.info("MECE passed attempt %d for '%s'", attempt+1, node.statement[:50])
                return children
            if attempt < MECE_MAX_RETRIES - 1:
                children = self.decomposer.decompose(parent=node, industry=industry, company=company, question=question, previous_issues=validation)
        return best_children

    def _decompose_recursive(self, node, industry, company, question, target_depth):
        if node.depth >= target_depth:
            node.is_leaf = True
            return
        if not node.children:
            children = self._decompose_with_validation(node, industry, company, question)
            for child in children:
                child.parent_id = node.id
                child.depth = node.depth + 1
                node.children.append(child)
        for child in node.children:
            self._decompose_recursive(child, industry, company, question, target_depth)

    def _classify_and_design(self, node, industry, company, question):
        if not node.is_leaf:
            for child in node.children:
                self._classify_and_design(child, industry, company, question)
            return
        testability = self.testability_classifier.classify(node=node, industry=industry, company=company, question=question)
        node.testability = testability
        if testability.classification != TestabilityClass.ASSUMPTION or testability.impact_score >= 4:
            node.analysis = self.analysis_designer.design(node=node, testability=testability, industry=industry, company=company, question=question)

    def generate_tree(self, industry: str, company: str, question: str) -> HypothesisTree:
        logger.info("Starting tree generation: %s / %s / %s", industry, company, question)

        classification = self.classify_question(industry, company, question)
        logger.info("Classification: %s (%.2f)", classification.question_type, classification.confidence)

        root = self.generate_root_and_branches(industry, company, question, classification)
        logger.info("Root generated with %d branches", len(root.children))

        self._decompose_recursive(root, industry, company, question, TARGET_TREE_DEPTH)
        all_nodes = self._collect_all(root)
        logger.info("Phase 1 complete: %d nodes, %d leaves", len(all_nodes), len([n for n in all_nodes if n.is_leaf]))

        logger.info("Phase 2: testability + analysis...")
        self._classify_and_design(root, industry, company, question)
        logger.info("Phase 2 complete")

        logger.info("Phase 3: data pre-population...")
        self.data_retrieval.retrieve_for_tree(root, industry, company, question)
        logger.info("Phase 3 complete")

        tree = HypothesisTree(root=root, classification=classification, industry=industry, company=company, question=question)

        logger.info("Phase 4: stress-testing...")
        tree.stress_test_report = self.red_team.stress_test(tree)
        logger.info("Phase 4 complete")

        logger.info("Phase 5: causal DAG construction...")
        tree.causal_dag = self.dag_builder.build_dag(root)
        logger.info("Phase 5 complete")

        return tree

    @staticmethod
    def _collect_all(node):
        result = [node]
        for child in node.children:
            result.extend(OrchestratorAgent._collect_all(child))
        return result
PYEOF

# ======================== API: scenario toggle endpoint ========================
cat > apps/api/app/routers/trees.py << 'PYEOF'
"""Tree and DAG endpoints — scenario toggling."""
from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from packages.agents.graph.state import propagate_states
from packages.shared.types import HypothesisState, ScenarioConfig

logger = logging.getLogger(__name__)

router = APIRouter(tags=["trees"])

# Reference to project store (imported at runtime)
from app.routers.projects import _projects


class ToggleRequest(BaseModel):
    node_id: str
    state: HypothesisState


class ScenarioSaveRequest(BaseModel):
    name: str


@router.post("/projects/{project_id}/dag/toggle")
async def toggle_node(project_id: str, body: ToggleRequest):
    project = _projects.get(project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")
    tree = project.get("tree")
    if not tree or not tree.causal_dag:
        raise HTTPException(status_code=400, detail="No DAG available")

    dag = propagate_states(tree.causal_dag, body.node_id, body.state)
    tree.causal_dag = dag

    return {
        "node_states": {k: v.value for k, v in dag.node_states.items()},
        "node_probabilities": dag.node_probabilities,
    }


@router.post("/projects/{project_id}/scenarios")
async def save_scenario(project_id: str, body: ScenarioSaveRequest):
    project = _projects.get(project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")
    tree = project.get("tree")
    if not tree or not tree.causal_dag:
        raise HTTPException(status_code=400, detail="No DAG available")

    scenario = ScenarioConfig(
        name=body.name,
        node_states=dict(tree.causal_dag.node_states),
        node_probabilities=dict(tree.causal_dag.node_probabilities),
    )
    tree.scenarios.append(scenario)
    return {"id": scenario.id, "name": scenario.name}


@router.get("/projects/{project_id}/scenarios")
async def list_scenarios(project_id: str):
    project = _projects.get(project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")
    tree = project.get("tree")
    if not tree:
        raise HTTPException(status_code=400, detail="No tree available")
    return [{"id": s.id, "name": s.name, "created_at": s.created_at.isoformat()} for s in tree.scenarios]
PYEOF

# ======================== UPDATE MAIN to include trees router ========================
cat > apps/api/app/main.py << 'PYEOF'
import logging
import os
import sys

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.routers import health, projects, trees

logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)

app = FastAPI(title="HypoTree API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins.split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(projects.router, prefix="/api")
app.include_router(trees.router, prefix="/api")
PYEOF

# ======================== FRONTEND: API client update ========================
cat > apps/web/src/lib/api.ts << 'TSEOF'
import type { Project, ProjectCreate } from '@/types/project';

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(body.detail || `HTTP ${res.status}`);
  }
  return res.json() as Promise<T>;
}

export const api = {
  createProject: (data: ProjectCreate) =>
    request<Project>('/api/projects', { method: 'POST', body: JSON.stringify(data) }),

  generateTree: (projectId: string) =>
    request<Project>(`/api/projects/${projectId}/generate`, { method: 'POST' }),

  getProject: (projectId: string) =>
    request<Project>(`/api/projects/${projectId}`),

  listProjects: () =>
    request<Project[]>('/api/projects'),

  toggleNode: (projectId: string, nodeId: string, state: string) =>
    request<{ node_states: Record<string, string>; node_probabilities: Record<string, number> }>(
      `/api/projects/${projectId}/dag/toggle`,
      { method: 'POST', body: JSON.stringify({ node_id: nodeId, state }) },
    ),

  saveScenario: (projectId: string, name: string) =>
    request<{ id: string; name: string }>(
      `/api/projects/${projectId}/scenarios`,
      { method: 'POST', body: JSON.stringify({ name }) },
    ),
};
TSEOF

# ======================== FRONTEND TYPES update ========================
cat > apps/web/src/types/hypothesis.ts << 'TSEOF'
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
export interface HypothesisTree { id: string; root: HypothesisNode; classification: ClassificationResult; industry: string; company: string; question: string; created_at: string; metadata: Record<string, unknown>; stress_test_report: StressTestReport | null; causal_dag: CausalDAG | null; scenarios: ScenarioConfig[]; }
TSEOF

# ======================== SCENARIO DAG VIEW COMPONENT ========================
mkdir -p apps/web/src/components/dag

cat > apps/web/src/components/dag/ScenarioDAGView.tsx << 'TSEOF'
import { useState, useCallback } from 'react';
import type { HypothesisTree, HypothesisNode, HypothesisState, CausalDAG } from '@/types/hypothesis';
import { api } from '@/lib/api';
import { cn } from '@/lib/utils';

const STATE_STYLES: Record<HypothesisState, { bg: string; border: string; text: string; label: string }> = {
  true: { bg: 'bg-green-50', border: 'border-green-400', text: 'text-green-700', label: 'TRUE' },
  false: { bg: 'bg-red-50', border: 'border-red-400', text: 'text-red-700', label: 'FALSE' },
  uncertain: { bg: 'bg-slate-50', border: 'border-slate-300', text: 'text-slate-600', label: '?' },
};

function collectAll(node: HypothesisNode): HypothesisNode[] {
  const result: HypothesisNode[] = [node];
  for (const child of node.children) {
    result.push(...collectAll(child));
  }
  return result;
}

interface Props {
  tree: HypothesisTree;
  projectId: string;
}

export function ScenarioDAGView({ tree, projectId }: Props) {
  const [dag, setDag] = useState<CausalDAG | null>(tree.causal_dag);
  const [toggling, setToggling] = useState<string | null>(null);
  const [scenarioName, setScenarioName] = useState('');
  const [savedScenarios, setSavedScenarios] = useState<Array<{ id: string; name: string }>>([]);

  const allNodes = collectAll(tree.root);
  const interactiveNodes = allNodes.filter((n) => n.depth <= 2);

  const handleToggle = useCallback(async (nodeId: string, newState: HypothesisState) => {
    setToggling(nodeId);
    try {
      const result = await api.toggleNode(projectId, nodeId, newState);
      setDag((prev) => prev ? {
        ...prev,
        node_states: Object.fromEntries(
          Object.entries(result.node_states).map(([k, v]) => [k, v as HypothesisState])
        ),
        node_probabilities: result.node_probabilities,
      } : null);
    } catch (e) {
      console.error('Toggle failed:', e);
    } finally {
      setToggling(null);
    }
  }, [projectId]);

  const handleSaveScenario = async () => {
    if (!scenarioName.trim()) return;
    try {
      const result = await api.saveScenario(projectId, scenarioName.trim());
      setSavedScenarios((prev) => [...prev, result]);
      setScenarioName('');
    } catch (e) {
      console.error('Save scenario failed:', e);
    }
  };

  const cycleState = (current: HypothesisState): HypothesisState => {
    if (current === 'uncertain') return 'true';
    if (current === 'true') return 'false';
    return 'uncertain';
  };

  if (!dag) return <p className="text-slate-500 text-center py-8">No causal DAG available.</p>;

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold text-slate-800">Scenario Modeling</h3>
          <p className="text-sm text-slate-500 mt-1">
            Toggle hypothesis states to see cascading effects. Click a node to cycle: UNCERTAIN {'\u2192'} TRUE {'\u2192'} FALSE {'\u2192'} UNCERTAIN
          </p>
        </div>
        <div className="flex items-center gap-2">
          <input
            type="text"
            value={scenarioName}
            onChange={(e) => setScenarioName(e.target.value)}
            placeholder="Scenario name"
            className="text-sm border border-slate-300 rounded-lg px-2 py-1 w-40"
          />
          <button
            onClick={handleSaveScenario}
            disabled={!scenarioName.trim()}
            className="text-sm bg-blue-600 text-white px-3 py-1 rounded-lg disabled:bg-slate-300"
          >
            Save
          </button>
        </div>
      </div>

      {savedScenarios.length > 0 && (
        <div className="flex gap-2 mb-4">
          {savedScenarios.map((s) => (
            <span key={s.id} className="text-xs bg-slate-100 text-slate-600 px-2 py-1 rounded-full">
              {s.name}
            </span>
          ))}
        </div>
      )}

      <div className="space-y-1">
        {interactiveNodes.map((node) => {
          const state = dag.node_states[node.id] ?? 'uncertain';
          const prob = dag.node_probabilities[node.id] ?? 0.5;
          const style = STATE_STYLES[state];
          const isToggling = toggling === node.id;

          return (
            <div
              key={node.id}
              className={cn(
                'flex items-center gap-3 p-3 rounded-lg border cursor-pointer transition-all',
                style.bg, style.border,
                isToggling && 'opacity-50',
              )}
              style={{ marginLeft: `${node.depth * 24}px` }}
              onClick={() => !isToggling && handleToggle(node.id, cycleState(state))}
            >
              <div className={cn(
                'w-16 text-center text-xs font-bold py-1 rounded',
                style.bg, style.text, 'border', style.border,
              )}>
                {style.label}
              </div>

              <div className="flex-1 min-w-0">
                <p className="text-sm text-slate-800">{node.statement}</p>
                <span className="text-xs text-slate-400 font-mono">d{node.depth} &middot; {node.id}</span>
              </div>

              <div className="text-right flex-shrink-0">
                <div className="w-20 bg-slate-200 rounded-full h-2">
                  <div
                    className={cn(
                      'h-2 rounded-full transition-all duration-500',
                      prob >= 0.7 ? 'bg-green-500' : prob <= 0.3 ? 'bg-red-500' : 'bg-amber-400',
                    )}
                    style={{ width: `${prob * 100}%` }}
                  />
                </div>
                <p className="text-xs text-slate-400 mt-0.5">{(prob * 100).toFixed(0)}%</p>
              </div>
            </div>
          );
        })}
      </div>

      <div className="mt-6 p-4 bg-slate-50 rounded-lg">
        <h4 className="text-sm font-medium text-slate-500 mb-2">DAG Statistics</h4>
        <div className="grid grid-cols-4 gap-4 text-center text-sm">
          <div>
            <p className="text-lg font-semibold text-green-600">
              {Object.values(dag.node_states).filter((s) => s === 'true').length}
            </p>
            <p className="text-xs text-slate-400">TRUE</p>
          </div>
          <div>
            <p className="text-lg font-semibold text-red-600">
              {Object.values(dag.node_states).filter((s) => s === 'false').length}
            </p>
            <p className="text-xs text-slate-400">FALSE</p>
          </div>
          <div>
            <p className="text-lg font-semibold text-slate-600">
              {Object.values(dag.node_states).filter((s) => s === 'uncertain').length}
            </p>
            <p className="text-xs text-slate-400">UNCERTAIN</p>
          </div>
          <div>
            <p className="text-lg font-semibold text-blue-600">{dag.edges.length}</p>
            <p className="text-xs text-slate-400">Dependencies</p>
          </div>
        </div>
      </div>
    </div>
  );
}
TSEOF

# ======================== UPDATED APP — add DAG tab ========================
cat > apps/web/src/App.tsx << 'TSEOF'
import { useState } from 'react';
import { QuestionInput } from '@/components/forms/QuestionInput';
import { HypothesisTreeView } from '@/components/tree/HypothesisTree';
import { AnalysisPlanTable } from '@/components/analysis/AnalysisPlanTable';
import { StressTestReportView } from '@/components/stress-test/StressTestReport';
import { ScenarioDAGView } from '@/components/dag/ScenarioDAGView';
import { LoadingState } from '@/components/common/LoadingState';
import { ErrorBoundary } from '@/components/common/ErrorBoundary';
import { api } from '@/lib/api';
import type { Project, ProjectCreate } from '@/types/project';

type ViewMode = 'tree' | 'table' | 'stress' | 'dag';

function App() {
  const [project, setProject] = useState<Project | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [viewMode, setViewMode] = useState<ViewMode>('tree');

  const handleSubmit = async (data: ProjectCreate) => {
    setLoading(true);
    setError(null);
    try {
      const created = await api.createProject(data);
      const generated = await api.generateTree(created.id);
      setProject(generated);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  const handleReset = () => { setProject(null); setError(null); setViewMode('tree'); };

  const tabs: { key: ViewMode; label: string; show: boolean; badge?: string }[] = [
    { key: 'tree', label: 'Tree View', show: true },
    { key: 'table', label: 'Analysis Plan', show: true },
    { key: 'stress', label: 'Stress Test', show: !!project?.tree?.stress_test_report,
      badge: project?.tree?.stress_test_report ? String(project.tree.stress_test_report.critical_count) : undefined },
    { key: 'dag', label: 'Scenarios', show: !!project?.tree?.causal_dag },
  ];

  return (
    <ErrorBoundary>
      <div className="min-h-screen bg-slate-50">
        <header className="bg-white border-b border-slate-200 px-6 py-4">
          <div className="flex items-center justify-between max-w-7xl mx-auto">
            <h1 className="text-xl font-bold text-slate-800 cursor-pointer" onClick={handleReset}>HypoTree</h1>
            <div className="flex items-center gap-4">
              {project?.tree && (
                <div className="flex bg-slate-100 rounded-lg p-0.5">
                  {tabs.filter((t) => t.show).map((tab) => (
                    <button key={tab.key} onClick={() => setViewMode(tab.key)}
                      className={`px-3 py-1 text-sm rounded-md transition-colors ${viewMode === tab.key ? 'bg-white text-slate-800 shadow-sm' : 'text-slate-500 hover:text-slate-700'}`}>
                      {tab.label}
                      {tab.badge && <span className="ml-1.5 inline-flex items-center justify-center w-5 h-5 text-xs bg-red-100 text-red-600 rounded-full">{tab.badge}</span>}
                    </button>
                  ))}
                </div>
              )}
              {project && <button onClick={handleReset} className="text-sm text-blue-600 hover:text-blue-700">New Question</button>}
            </div>
          </div>
        </header>

        <main className="max-w-7xl mx-auto py-8 px-6">
          {error && <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">{error}</div>}
          {loading && <LoadingState />}
          {!loading && !project && <QuestionInput onSubmit={handleSubmit} loading={loading} />}
          {!loading && project?.tree && (
            <div>
              <div className="mb-6 p-4 bg-white rounded-lg border border-slate-200">
                <div className="flex items-center gap-4 text-sm text-slate-600 flex-wrap">
                  <span><strong>Industry:</strong> {project.industry}</span>
                  <span><strong>Company:</strong> {project.company}</span>
                  <span><strong>Type:</strong> {project.tree.classification.question_type.replace(/_/g, ' ')}</span>
                  <span><strong>Framework:</strong> {project.tree.classification.framework.replace(/_/g, ' ')}</span>
                  <span><strong>Confidence:</strong> {(project.tree.classification.confidence * 100).toFixed(0)}%</span>
                </div>
                <p className="text-sm text-slate-500 mt-2">{project.question}</p>
              </div>
              {viewMode === 'tree' && <HypothesisTreeView root={project.tree.root} />}
              {viewMode === 'table' && <AnalysisPlanTable root={project.tree.root} />}
              {viewMode === 'stress' && project.tree.stress_test_report && <StressTestReportView report={project.tree.stress_test_report} />}
              {viewMode === 'dag' && project.tree.causal_dag && <ScenarioDAGView tree={project.tree} projectId={project.id} />}
            </div>
          )}
        </main>
      </div>
    </ErrorBoundary>
  );
}

export default App;
TSEOF

echo ""
echo "=== Phase 5 files written ==="
echo ""
echo "New features:"
echo "  - Causal DAG built from tree (parent-child edges + LLM-inferred cross-branch dependencies)"
echo "  - Interactive scenario toggling: click a node to cycle UNCERTAIN > TRUE > FALSE"
echo "  - Probability bars show cascading belief propagation"
echo "  - Save named scenarios for comparison"
echo "  - API endpoint: POST /api/projects/{id}/dag/toggle"
echo "  - New 'Scenarios' tab in the header"
echo ""
echo "Run: bash phase5.sh && restart uvicorn && generate a new tree"
echo "Then click the Scenarios tab and toggle hypothesis states."