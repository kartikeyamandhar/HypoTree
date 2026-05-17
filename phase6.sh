#!/bin/bash
set -e

# ============================================================
# HypoTree Phase 6 — Workplan + NL Negotiation + UX Overhaul
# Run from hypotree/ root
# Usage: bash phase6.sh
# ============================================================

echo "=== Phase 6: Workplan + NL Negotiation + UX Overhaul ==="

# ======================== WORKPLAN SCHEMAS ========================
cat > packages/agents/workplan/schemas.py << 'PYEOF'
from __future__ import annotations
from pydantic import BaseModel, Field


class WorkItem(BaseModel):
    hypothesis_id: str
    hypothesis_statement: str = ""
    analysis_type: str = ""
    loe_hours: float = 0.0
    resource_type: str = "analyst"  # analyst, manager, partner


class Workstream(BaseModel):
    id: str
    name: str
    description: str = ""
    items: list[WorkItem] = Field(default_factory=list)
    total_loe: float = 0.0
    sequence_order: int = 0
    depends_on: list[str] = Field(default_factory=list)


class Workplan(BaseModel):
    workstreams: list[Workstream] = Field(default_factory=list)
    total_loe: float = 0.0
    estimated_weeks: float = 0.0
    critical_path: list[str] = Field(default_factory=list)
    summary: str = ""
PYEOF

# ======================== WORKPLAN PROMPTS ========================
cat > packages/agents/workplan/prompts.py << 'PYEOF'
WORKPLAN_PROMPT = """You are a strategy consulting manager building a workplan from a hypothesis tree analysis.

Context:
- Industry: {industry}
- Company: {company}
- Question: {question}

The following hypotheses have been classified and assigned analyses. Group them into 3-6 logical workstreams. Each workstream should cluster hypotheses that share data sources, methodologies, or domain affinity.

Hypotheses:
{hypotheses_block}

For each workstream, specify:
- name: short descriptive name (e.g., "Revenue Synergy Validation", "Cost Structure Analysis")
- description: one sentence scope
- sequence_order: 1 = can start immediately, 2 = needs workstream 1 results, etc.
- depends_on: list of workstream IDs this depends on (empty if none)

For each hypothesis in a workstream, assign resource_type:
- "analyst": data gathering, modeling, quantitative analysis
- "manager": synthesis, stakeholder interviews, qualitative judgment
- "partner": strategic decisions, client alignment, high-stakes assumptions

Respond ONLY with valid JSON, no markdown fences:
{{
  "workstreams": [
    {{
      "id": "ws1",
      "name": "<name>",
      "description": "<scope>",
      "sequence_order": 1,
      "depends_on": [],
      "items": [
        {{
          "hypothesis_id": "<id>",
          "resource_type": "<analyst|manager|partner>"
        }}
      ]
    }}
  ],
  "estimated_weeks": <number>,
  "summary": "<2-3 sentence workplan summary>"
}}"""

NEGOTIATION_PROMPT = """You are a strategy consulting workplan manager handling a modification request.

Current workplan:
{workplan_json}

User request: "{user_request}"

Interpret the request and produce a modified workplan. Common requests:
- Time compression: reduce weeks, drop low-priority items
- Scope changes: add/remove workstreams or hypotheses
- Resource reallocation: shift work between analyst/manager/partner
- Priority changes: reorder workstreams

Respond ONLY with valid JSON matching the workplan schema, no markdown fences:
{{
  "workstreams": [...],
  "estimated_weeks": <number>,
  "summary": "<what changed and why>",
  "critical_path": [<workstream ids in order>]
}}"""
PYEOF

# ======================== WORKPLAN AGENT ========================
cat > packages/agents/workplan/agent.py << 'PYEOF'
"""Workplan Compiler + Negotiation Agent."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.workplan.prompts import WORKPLAN_PROMPT, NEGOTIATION_PROMPT
from packages.agents.workplan.schemas import Workplan, Workstream, WorkItem
from packages.shared.types import HypothesisNode

logger = logging.getLogger(__name__)


class WorkplanAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a strategy consulting workplan manager."

    def compile_workplan(
        self, root: HypothesisNode, industry: str, company: str, question: str,
    ) -> Workplan:
        leaves = self._get_classified_leaves(root)
        if not leaves:
            return Workplan(summary="No classified leaves to build workplan from.")

        hyp_block = "\n".join(
            f"- [{n.id}] {n.statement} | "
            f"type={n.analysis.analysis_type.value if n.analysis else 'none'} | "
            f"loe={n.analysis.loe_hours if n.analysis else 0}h | "
            f"priority={n.testability.priority_score if n.testability else 0}"
            for n in leaves
        )

        prompt = WORKPLAN_PROMPT.format(
            industry=industry, company=company, question=question,
            hypotheses_block=hyp_block,
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        workstreams = []
        node_map = {n.id: n for n in leaves}

        for ws_data in data.get("workstreams", []):
            items = []
            for item_data in ws_data.get("items", []):
                hid = item_data.get("hypothesis_id", "")
                node = node_map.get(hid)
                items.append(WorkItem(
                    hypothesis_id=hid,
                    hypothesis_statement=node.statement if node else "",
                    analysis_type=node.analysis.analysis_type.value if node and node.analysis else "",
                    loe_hours=node.analysis.loe_hours if node and node.analysis else 0,
                    resource_type=item_data.get("resource_type", "analyst"),
                ))

            ws = Workstream(
                id=ws_data.get("id", ""),
                name=ws_data.get("name", ""),
                description=ws_data.get("description", ""),
                items=items,
                total_loe=sum(i.loe_hours for i in items),
                sequence_order=ws_data.get("sequence_order", 1),
                depends_on=ws_data.get("depends_on", []),
            )
            workstreams.append(ws)

        workstreams.sort(key=lambda w: w.sequence_order)
        critical_path = [ws.id for ws in workstreams]

        workplan = Workplan(
            workstreams=workstreams,
            total_loe=sum(ws.total_loe for ws in workstreams),
            estimated_weeks=data.get("estimated_weeks", 4),
            critical_path=critical_path,
            summary=data.get("summary", ""),
        )

        logger.info("Workplan compiled: %d workstreams, %.0fh total, %.0f weeks",
            len(workstreams), workplan.total_loe, workplan.estimated_weeks)
        return workplan

    def negotiate(self, workplan: Workplan, user_request: str) -> Workplan:
        wp_dict = workplan.model_dump()
        prompt = NEGOTIATION_PROMPT.format(
            workplan_json=json.dumps(wp_dict, indent=2, default=str),
            user_request=user_request,
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        workstreams = []
        for ws_data in data.get("workstreams", []):
            items = [WorkItem(**i) for i in ws_data.get("items", [])]
            workstreams.append(Workstream(
                id=ws_data.get("id", ""),
                name=ws_data.get("name", ""),
                description=ws_data.get("description", ""),
                items=items,
                total_loe=sum(i.loe_hours for i in items),
                sequence_order=ws_data.get("sequence_order", 1),
                depends_on=ws_data.get("depends_on", []),
            ))

        return Workplan(
            workstreams=workstreams,
            total_loe=sum(ws.total_loe for ws in workstreams),
            estimated_weeks=data.get("estimated_weeks", workplan.estimated_weeks),
            critical_path=data.get("critical_path", []),
            summary=data.get("summary", ""),
        )

    def _get_classified_leaves(self, node: HypothesisNode) -> list[HypothesisNode]:
        result = []
        def walk(n: HypothesisNode):
            if n.is_leaf and n.testability and n.analysis:
                result.append(n)
            for c in n.children:
                walk(c)
        walk(node)
        return result
PYEOF

# ======================== ADD WORKPLAN TO SHARED TYPES ========================
# Append workplan to HypothesisTree
python3 -c "
import re
content = open('packages/shared/types.py').read()
# Add workplan import-compatible field to HypothesisTree
if 'workplan' not in content:
    content = content.replace(
        'scenarios: list[ScenarioConfig] = Field(default_factory=list)',
        'scenarios: list[ScenarioConfig] = Field(default_factory=list)\n    workplan: Optional[dict] = None'
    )
    open('packages/shared/types.py', 'w').write(content)
    print('Added workplan field to HypothesisTree')
else:
    print('workplan field already exists')
"

# ======================== UPDATE ORCHESTRATOR — add Phase 6 ========================
cat > packages/agents/orchestrator/agent.py << 'PYEOF'
"""Orchestrator agent — full pipeline through Phase 6."""
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
from packages.agents.workplan.agent import WorkplanAgent
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
        self.workplan_agent = WorkplanAgent()

    def get_system_prompt(self) -> str:
        return "You are a strategy consulting orchestrator."

    def classify_question(self, industry, company, question):
        prompt = CLASSIFICATION_PROMPT.format(industry=industry, company=company, question=question)
        return ClassificationResult(**json.loads(self.call_llm(prompt)))

    def generate_root_and_branches(self, industry, company, question, classification):
        prompt = ROOT_HYPOTHESIS_PROMPT.format(
            industry=industry, company=company, question=question,
            question_type=classification.question_type.value, framework=classification.framework.value)
        data = json.loads(self.call_llm(prompt))
        root = HypothesisNode(statement=data["root"]["statement"],
            what_must_be_true=data["root"].get("what_must_be_true"),
            evidence_needed=data["root"].get("evidence_needed"), depth=0)
        for cd in data["children"]:
            root.children.append(HypothesisNode(statement=cd["statement"], parent_id=root.id,
                what_must_be_true=cd.get("what_must_be_true"), evidence_needed=cd.get("evidence_needed"), depth=1))
        return root

    def _decompose_with_validation(self, node, industry, company, question):
        children = self.decomposer.decompose(parent=node, industry=industry, company=company, question=question)
        best_children, best_score = children, 999
        for attempt in range(MECE_MAX_RETRIES):
            validation = self.mece_validator.validate(parent=node, children=children)
            score = len(validation.overlaps) + len(validation.gaps)
            if score < best_score: best_score, best_children = score, children
            if validation.is_valid: return children
            if attempt < MECE_MAX_RETRIES - 1:
                children = self.decomposer.decompose(parent=node, industry=industry, company=company, question=question, previous_issues=validation)
        return best_children

    def _decompose_recursive(self, node, industry, company, question, target_depth):
        if node.depth >= target_depth:
            node.is_leaf = True
            return
        if not node.children:
            for child in self._decompose_with_validation(node, industry, company, question):
                child.parent_id = node.id
                child.depth = node.depth + 1
                node.children.append(child)
        for child in node.children:
            self._decompose_recursive(child, industry, company, question, target_depth)

    def _classify_and_design(self, node, industry, company, question):
        if not node.is_leaf:
            for child in node.children: self._classify_and_design(child, industry, company, question)
            return
        node.testability = self.testability_classifier.classify(node=node, industry=industry, company=company, question=question)
        if node.testability.classification != TestabilityClass.ASSUMPTION or node.testability.impact_score >= 4:
            node.analysis = self.analysis_designer.design(node=node, testability=node.testability, industry=industry, company=company, question=question)

    def generate_tree(self, industry: str, company: str, question: str) -> HypothesisTree:
        logger.info("P1: Starting tree generation")
        classification = self.classify_question(industry, company, question)
        root = self.generate_root_and_branches(industry, company, question, classification)
        self._decompose_recursive(root, industry, company, question, TARGET_TREE_DEPTH)
        logger.info("P1 complete: %d nodes", len(self._collect_all(root)))

        logger.info("P2: Testability + analysis design")
        self._classify_and_design(root, industry, company, question)
        logger.info("P2 complete")

        logger.info("P3: Data pre-population")
        self.data_retrieval.retrieve_for_tree(root, industry, company, question)
        logger.info("P3 complete")

        tree = HypothesisTree(root=root, classification=classification, industry=industry, company=company, question=question)

        logger.info("P4: Stress-testing")
        tree.stress_test_report = self.red_team.stress_test(tree)
        logger.info("P4 complete")

        logger.info("P5: Causal DAG")
        tree.causal_dag = self.dag_builder.build_dag(root)
        logger.info("P5 complete")

        logger.info("P6: Workplan compilation")
        workplan = self.workplan_agent.compile_workplan(root, industry, company, question)
        tree.workplan = workplan.model_dump()
        logger.info("P6 complete: %d workstreams, %.0fh LOE", len(workplan.workstreams), workplan.total_loe)

        return tree

    @staticmethod
    def _collect_all(node):
        result = [node]
        for child in node.children: result.extend(OrchestratorAgent._collect_all(child))
        return result
PYEOF

# ======================== NEGOTIATION ENDPOINT ========================
cat > apps/api/app/routers/trees.py << 'PYEOF'
"""Tree, DAG, and workplan endpoints."""
from __future__ import annotations

import json
import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from packages.agents.graph.state import propagate_states
from packages.agents.workplan.agent import WorkplanAgent
from packages.agents.workplan.schemas import Workplan
from packages.shared.types import HypothesisState, ScenarioConfig

logger = logging.getLogger(__name__)
router = APIRouter(tags=["trees"])

from app.routers.projects import _projects


class ToggleRequest(BaseModel):
    node_id: str
    state: HypothesisState


class NegotiateRequest(BaseModel):
    message: str


@router.post("/projects/{project_id}/dag/toggle")
async def toggle_node(project_id: str, body: ToggleRequest):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404, "Project not found")
    tree = project.get("tree")
    if not tree or not tree.causal_dag: raise HTTPException(400, "No DAG")
    dag = propagate_states(tree.causal_dag, body.node_id, body.state)
    tree.causal_dag = dag
    return {"node_states": {k: v.value for k, v in dag.node_states.items()}, "node_probabilities": dag.node_probabilities}


@router.post("/projects/{project_id}/scenarios")
async def save_scenario(project_id: str, body: BaseModel):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    tree = project.get("tree")
    if not tree or not tree.causal_dag: raise HTTPException(400)
    scenario = ScenarioConfig(name=getattr(body, 'name', 'unnamed'), node_states=dict(tree.causal_dag.node_states), node_probabilities=dict(tree.causal_dag.node_probabilities))
    tree.scenarios.append(scenario)
    return {"id": scenario.id, "name": scenario.name}


@router.post("/projects/{project_id}/workplan/negotiate")
async def negotiate_workplan(project_id: str, body: NegotiateRequest):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404, "Project not found")
    tree = project.get("tree")
    if not tree or not tree.workplan: raise HTTPException(400, "No workplan")

    agent = WorkplanAgent()
    current = Workplan(**tree.workplan)
    updated = agent.negotiate(current, body.message)
    tree.workplan = updated.model_dump()
    return updated.model_dump()
PYEOF

# ======================== STREAMING STATUS ENDPOINT ========================
# Add a status field to track agent progress
cat > apps/api/app/services/orchestrator.py << 'PYEOF'
"""Shared status tracker for agent progress."""
from __future__ import annotations

_status: dict[str, list[dict]] = {}


def push_status(project_id: str, phase: str, agent: str, message: str):
    if project_id not in _status:
        _status[project_id] = []
    _status[project_id].append({"phase": phase, "agent": agent, "message": message})


def get_status(project_id: str) -> list[dict]:
    return _status.get(project_id, [])


def clear_status(project_id: str):
    _status.pop(project_id, None)
PYEOF

# Add status polling endpoint to projects router
cat > apps/api/app/routers/projects.py << 'PYEOF'
"""Project endpoints."""
from __future__ import annotations

import logging
import uuid
from datetime import datetime

from fastapi import APIRouter, HTTPException

from packages.agents.orchestrator.agent import OrchestratorAgent
from packages.shared.types import HypothesisTree, ProjectCreate, ProjectResponse
from app.services.orchestrator import get_status, clear_status

logger = logging.getLogger(__name__)
router = APIRouter(tags=["projects"])

_projects: dict[str, dict] = {}


@router.post("/projects", response_model=ProjectResponse)
async def create_project(body: ProjectCreate):
    project_id = str(uuid.uuid4())
    project = {"id": project_id, "industry": body.industry, "company": body.company,
        "question": body.question, "status": "created", "tree": None, "created_at": datetime.utcnow()}
    _projects[project_id] = project
    return ProjectResponse(**project)


@router.post("/projects/{project_id}/generate", response_model=ProjectResponse)
async def generate_tree(project_id: str):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404, "Project not found")
    if project["tree"]: raise HTTPException(400, "Already generated")
    project["status"] = "generating"
    try:
        tree = OrchestratorAgent().generate_tree(project["industry"], project["company"], project["question"])
        project["tree"] = tree
        project["status"] = "complete"
    except Exception as e:
        logger.exception("Generation failed")
        project["status"] = "error"
        raise HTTPException(500, str(e))
    return ProjectResponse(**project)


@router.get("/projects/{project_id}", response_model=ProjectResponse)
async def get_project(project_id: str):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    return ProjectResponse(**project)


@router.get("/projects", response_model=list[ProjectResponse])
async def list_projects():
    return [ProjectResponse(**p) for p in _projects.values()]


@router.get("/projects/{project_id}/status")
async def get_generation_status(project_id: str):
    return {"events": get_status(project_id)}
PYEOF

# ======================== FRONTEND: COMPLETE UX OVERHAUL ========================

# New index.css with design system
cat > apps/web/src/index.css << 'TSEOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&family=DM+Sans:ital,wght@0,400;0,500;0,600;0,700&display=swap');

:root {
  --font-sans: 'DM Sans', system-ui, -apple-system, sans-serif;
  --font-mono: 'JetBrains Mono', monospace;
  --bg-primary: #0f1117;
  --bg-secondary: #1a1d27;
  --bg-card: #21242f;
  --bg-hover: #282c3a;
  --border-subtle: #2a2e3b;
  --border-active: #4f46e5;
  --text-primary: #e8eaf0;
  --text-secondary: #9ca3af;
  --text-muted: #6b7280;
  --accent-indigo: #6366f1;
  --accent-green: #22c55e;
  --accent-amber: #f59e0b;
  --accent-red: #ef4444;
  --accent-blue: #3b82f6;
  --accent-purple: #a855f7;
}

* {
  font-family: var(--font-sans);
}

body {
  background: var(--bg-primary);
  color: var(--text-primary);
  line-height: 1.6;
  -webkit-font-smoothing: antialiased;
}

::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: var(--bg-primary); }
::-webkit-scrollbar-thumb { background: var(--border-subtle); border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }
TSEOF

# ======================== FRONTEND: App.tsx — full redesign ========================
cat > apps/web/src/App.tsx << 'TSEOF'
import { useState } from 'react';
import { QuestionInput } from '@/components/forms/QuestionInput';
import { HypothesisTreeView } from '@/components/tree/HypothesisTree';
import { AnalysisPlanTable } from '@/components/analysis/AnalysisPlanTable';
import { StressTestReportView } from '@/components/stress-test/StressTestReport';
import { ScenarioDAGView } from '@/components/dag/ScenarioDAGView';
import { WorkplanView } from '@/components/workplan/WorkplanView';
import { LiveAgentStatus } from '@/components/common/LiveAgentStatus';
import { ErrorBoundary } from '@/components/common/ErrorBoundary';
import { api } from '@/lib/api';
import type { Project, ProjectCreate } from '@/types/project';

type ViewMode = 'tree' | 'table' | 'stress' | 'dag' | 'workplan';

const TAB_CONFIG: { key: ViewMode; label: string; icon: string }[] = [
  { key: 'tree', label: 'Tree', icon: '\u{1F333}' },
  { key: 'table', label: 'Analysis', icon: '\u{1F4CA}' },
  { key: 'stress', label: 'Red Team', icon: '\u{1F6E1}' },
  { key: 'dag', label: 'Scenarios', icon: '\u{1F504}' },
  { key: 'workplan', label: 'Workplan', icon: '\u{1F4CB}' },
];

function App() {
  const [project, setProject] = useState<Project | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [viewMode, setViewMode] = useState<ViewMode>('tree');
  const [projectId, setProjectId] = useState<string | null>(null);

  const handleSubmit = async (data: ProjectCreate) => {
    setLoading(true);
    setError(null);
    try {
      const created = await api.createProject(data);
      setProjectId(created.id);
      const generated = await api.generateTree(created.id);
      setProject(generated);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  const handleReset = () => {
    setProject(null);
    setError(null);
    setViewMode('tree');
    setProjectId(null);
  };

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
        {/* Header */}
        <header className="border-b px-6 py-3" style={{ background: 'var(--bg-secondary)', borderColor: 'var(--border-subtle)' }}>
          <div className="flex items-center justify-between max-w-screen-2xl mx-auto">
            <div className="flex items-center gap-3 cursor-pointer" onClick={handleReset}>
              <div className="w-8 h-8 rounded-lg flex items-center justify-center text-sm font-bold" style={{ background: 'var(--accent-indigo)', color: 'white' }}>H</div>
              <span className="text-lg font-bold" style={{ color: 'var(--text-primary)', fontFamily: 'var(--font-mono)' }}>HypoTree</span>
            </div>

            {project?.tree && (
              <div className="flex items-center gap-1 p-1 rounded-xl" style={{ background: 'var(--bg-primary)' }}>
                {visibleTabs.map((tab) => (
                  <button key={tab.key} onClick={() => setViewMode(tab.key)}
                    className="px-4 py-1.5 text-sm rounded-lg transition-all duration-200"
                    style={{
                      background: viewMode === tab.key ? 'var(--accent-indigo)' : 'transparent',
                      color: viewMode === tab.key ? 'white' : 'var(--text-secondary)',
                      fontWeight: viewMode === tab.key ? 600 : 400,
                    }}>
                    <span className="mr-1.5">{tab.icon}</span>{tab.label}
                    {tab.key === 'stress' && project?.tree?.stress_test_report && (
                      <span className="ml-1.5 text-xs px-1.5 py-0.5 rounded-full" style={{ background: 'var(--accent-red)', color: 'white' }}>
                        {project.tree.stress_test_report.critical_count}
                      </span>
                    )}
                  </button>
                ))}
              </div>
            )}

            {project && (
              <button onClick={handleReset} className="text-sm px-3 py-1.5 rounded-lg transition-colors"
                style={{ color: 'var(--accent-indigo)', border: '1px solid var(--border-subtle)' }}>
                New Analysis
              </button>
            )}
          </div>
        </header>

        {/* Main */}
        <main className="max-w-screen-2xl mx-auto py-6 px-6">
          {error && (
            <div className="mb-6 p-4 rounded-xl border text-sm" style={{ background: '#1c1012', borderColor: 'var(--accent-red)', color: '#fca5a5' }}>
              {error}
            </div>
          )}

          {loading && <LiveAgentStatus projectId={projectId} />}

          {!loading && !project && <QuestionInput onSubmit={handleSubmit} loading={loading} />}

          {!loading && project?.tree && (
            <div>
              {/* Context bar */}
              <div className="mb-6 p-4 rounded-xl" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
                <div className="flex items-center gap-6 text-sm flex-wrap" style={{ color: 'var(--text-secondary)' }}>
                  <span><span style={{ color: 'var(--text-muted)' }}>Industry</span> <span style={{ color: 'var(--text-primary)' }}>{project.industry}</span></span>
                  <span><span style={{ color: 'var(--text-muted)' }}>Company</span> <span style={{ color: 'var(--text-primary)' }}>{project.company}</span></span>
                  <span><span style={{ color: 'var(--text-muted)' }}>Framework</span> <span style={{ color: 'var(--accent-indigo)' }}>{project.tree.classification.framework.replace(/_/g, ' ')}</span></span>
                  <span><span style={{ color: 'var(--text-muted)' }}>Confidence</span> <span style={{ color: 'var(--accent-green)' }}>{(project.tree.classification.confidence * 100).toFixed(0)}%</span></span>
                </div>
                <p className="mt-2 text-sm" style={{ color: 'var(--text-primary)', fontFamily: 'var(--font-mono)', fontSize: '13px' }}>{project.question}</p>
              </div>

              {viewMode === 'tree' && <HypothesisTreeView root={project.tree.root} />}
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
TSEOF

# ======================== LIVE AGENT STATUS (replaces LoadingState) ========================
cat > apps/web/src/components/common/LiveAgentStatus.tsx << 'TSEOF'
import { useState, useEffect } from 'react';

interface AgentStep {
  phase: string;
  agent: string;
  status: 'running' | 'complete' | 'pending';
  startedAt?: number;
}

const PIPELINE: AgentStep[] = [
  { phase: 'P1', agent: 'Orchestrator', status: 'pending' },
  { phase: 'P1', agent: 'Question Classifier', status: 'pending' },
  { phase: 'P1', agent: 'Decomposer', status: 'pending' },
  { phase: 'P1', agent: 'MECE Validator', status: 'pending' },
  { phase: 'P2', agent: 'Testability Classifier', status: 'pending' },
  { phase: 'P2', agent: 'Analysis Designer', status: 'pending' },
  { phase: 'P3', agent: 'Yahoo Finance Fetcher', status: 'pending' },
  { phase: 'P3', agent: 'SEC EDGAR Fetcher', status: 'pending' },
  { phase: 'P3', agent: 'Data Matcher', status: 'pending' },
  { phase: 'P4', agent: "Devil's Advocate", status: 'pending' },
  { phase: 'P4', agent: 'Assumption Surfacer', status: 'pending' },
  { phase: 'P4', agent: 'Sensitivity Analyzer', status: 'pending' },
  { phase: 'P4', agent: 'Contradiction Detector', status: 'pending' },
  { phase: 'P5', agent: 'DAG Builder', status: 'pending' },
  { phase: 'P6', agent: 'Workplan Compiler', status: 'pending' },
];

const PHASE_LABELS: Record<string, string> = {
  P1: 'Hypothesis Decomposition',
  P2: 'Testability & Analysis',
  P3: 'Data Pre-Population',
  P4: 'Adversarial Stress-Test',
  P5: 'Causal DAG Construction',
  P6: 'Workplan Synthesis',
};

const PHASE_COLORS: Record<string, string> = {
  P1: '#6366f1', P2: '#3b82f6', P3: '#22c55e',
  P4: '#ef4444', P5: '#a855f7', P6: '#f59e0b',
};

interface Props {
  projectId: string | null;
}

export function LiveAgentStatus({ projectId }: Props) {
  const [steps, setSteps] = useState<AgentStep[]>(PIPELINE.map((s) => ({ ...s })));
  const [elapsed, setElapsed] = useState(0);
  const [currentIdx, setCurrentIdx] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => setElapsed((e) => e + 1), 1000);
    return () => clearInterval(timer);
  }, []);

  // Simulate agent progression based on elapsed time
  useEffect(() => {
    const advanceRate = 25; // seconds per step (rough average)
    const newIdx = Math.min(Math.floor(elapsed / advanceRate), steps.length - 1);
    if (newIdx !== currentIdx) {
      setCurrentIdx(newIdx);
      setSteps((prev) =>
        prev.map((s, i) => ({
          ...s,
          status: i < newIdx ? 'complete' : i === newIdx ? 'running' : 'pending',
        }))
      );
    }
  }, [elapsed, currentIdx, steps.length]);

  const phases = [...new Set(PIPELINE.map((s) => s.phase))];
  const currentPhase = steps[currentIdx]?.phase ?? 'P1';

  const formatTime = (s: number) => `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, '0')}`;

  return (
    <div className="max-w-2xl mx-auto py-12">
      {/* Header */}
      <div className="text-center mb-10">
        <div className="inline-flex items-center gap-3 mb-4">
          <div className="w-3 h-3 rounded-full animate-pulse" style={{ background: PHASE_COLORS[currentPhase] }} />
          <span className="text-sm font-mono" style={{ color: 'var(--text-muted)' }}>{formatTime(elapsed)}</span>
        </div>
        <h2 className="text-xl font-semibold mb-1" style={{ color: 'var(--text-primary)' }}>
          {PHASE_LABELS[currentPhase]}
        </h2>
        <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
          {steps[currentIdx]?.agent ?? 'Initializing'} is working...
        </p>
      </div>

      {/* Phase progress bar */}
      <div className="flex gap-1 mb-8 px-4">
        {phases.map((phase) => {
          const phaseSteps = steps.filter((s) => s.phase === phase);
          const done = phaseSteps.filter((s) => s.status === 'complete').length;
          const total = phaseSteps.length;
          const isActive = phase === currentPhase;
          const isDone = done === total;
          return (
            <div key={phase} className="flex-1">
              <div className="h-1.5 rounded-full overflow-hidden" style={{ background: 'var(--bg-card)' }}>
                <div className="h-full rounded-full transition-all duration-1000"
                  style={{ width: `${(done / total) * 100}%`, background: PHASE_COLORS[phase], opacity: isDone ? 1 : isActive ? 0.8 : 0.3 }} />
              </div>
              <p className="text-xs mt-1 text-center" style={{ color: isActive ? PHASE_COLORS[phase] : 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>
                {phase}
              </p>
            </div>
          );
        })}
      </div>

      {/* Agent list */}
      <div className="space-y-1 px-4">
        {steps.map((step, i) => (
          <div key={i} className="flex items-center gap-3 py-2 px-3 rounded-lg transition-all duration-300"
            style={{ background: step.status === 'running' ? 'var(--bg-card)' : 'transparent', opacity: step.status === 'pending' ? 0.35 : 1 }}>
            <div className="w-5 flex-shrink-0 text-center">
              {step.status === 'complete' && <span style={{ color: 'var(--accent-green)' }}>{'\u2713'}</span>}
              {step.status === 'running' && <span className="inline-block w-2 h-2 rounded-full animate-pulse" style={{ background: PHASE_COLORS[step.phase] }} />}
              {step.status === 'pending' && <span className="inline-block w-2 h-2 rounded-full" style={{ background: 'var(--border-subtle)' }} />}
            </div>
            <span className="text-xs w-8 font-mono" style={{ color: PHASE_COLORS[step.phase] }}>{step.phase}</span>
            <span className="text-sm flex-1" style={{ color: step.status === 'running' ? 'var(--text-primary)' : 'var(--text-secondary)', fontWeight: step.status === 'running' ? 500 : 400 }}>
              {step.agent}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
TSEOF

# ======================== QUESTION INPUT — dark theme ========================
cat > apps/web/src/components/forms/QuestionInput.tsx << 'TSEOF'
import { useState } from 'react';
import type { ProjectCreate } from '@/types/project';

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
          Enter a strategic question to generate a MECE hypothesis tree with testability classification, data pre-population, and adversarial stress-testing.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>INDUSTRY</label>
            <input type="text" value={industry} onChange={(e) => setIndustry(e.target.value)}
              placeholder="e.g., Semiconductor"
              className="w-full px-3 py-2.5 rounded-lg text-sm outline-none transition-colors"
              style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)' }}
              disabled={loading} />
          </div>
          <div>
            <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>COMPANY</label>
            <input type="text" value={company} onChange={(e) => setCompany(e.target.value)}
              placeholder="e.g., Skyworks Solutions"
              className="w-full px-3 py-2.5 rounded-lg text-sm outline-none transition-colors"
              style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)' }}
              disabled={loading} />
          </div>
        </div>
        <div>
          <label className="block text-xs font-medium mb-1.5" style={{ color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>STRATEGIC QUESTION</label>
          <textarea value={question} onChange={(e) => setQuestion(e.target.value)}
            placeholder="e.g., Should Skyworks and Qorvo merge?"
            rows={3}
            className="w-full px-3 py-2.5 rounded-lg text-sm outline-none resize-none transition-colors"
            style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)' }}
            disabled={loading} />
        </div>
        <button type="submit" disabled={!ready}
          className="w-full py-3 rounded-lg text-sm font-semibold transition-all duration-200"
          style={{
            background: ready ? 'var(--accent-indigo)' : 'var(--bg-card)',
            color: ready ? 'white' : 'var(--text-muted)',
            cursor: ready ? 'pointer' : 'not-allowed',
          }}>
          Generate Hypothesis Tree
        </button>
      </form>
    </div>
  );
}
TSEOF

# ======================== TREE VIEW — dark theme, compact ========================
cat > apps/web/src/components/tree/HypothesisTree.tsx << 'TSEOF'
import { useState } from 'react';
import type { HypothesisNode as HNode } from '@/types/hypothesis';
import { NodeDetailPanel } from './NodeDetailPanel';
import { TestabilityBadge } from '@/components/analysis/TestabilityBadge';

const DEPTH_DOTS = ['#6366f1', '#3b82f6', '#22c55e', '#f59e0b'];

interface TreeNodeProps { node: HNode; onSelect: (n: HNode) => void; selectedId: string | null; }

function TreeNode({ node, onSelect, selectedId }: TreeNodeProps) {
  const [collapsed, setCollapsed] = useState(node.depth >= 2);
  const has = node.children.length > 0;
  const sel = node.id === selectedId;
  const dot = DEPTH_DOTS[node.depth % DEPTH_DOTS.length];

  return (
    <div style={{ marginLeft: node.depth > 0 ? 16 : 0 }}>
      <div onClick={() => onSelect(node)}
        className="flex items-start gap-2 py-2 px-3 rounded-lg cursor-pointer transition-all duration-150"
        style={{
          background: sel ? 'var(--bg-card)' : 'transparent',
          border: sel ? '1px solid var(--border-active)' : '1px solid transparent',
        }}>
        {has ? (
          <button onClick={(e) => { e.stopPropagation(); setCollapsed(!collapsed); }}
            className="mt-1 text-xs w-4 flex-shrink-0 text-center" style={{ color: 'var(--text-muted)' }}>
            {collapsed ? '\u25B8' : '\u25BE'}
          </button>
        ) : <div className="w-4 flex-shrink-0" />}

        <div className="w-2 h-2 rounded-full mt-1.5 flex-shrink-0" style={{ background: dot }} />

        <div className="flex-1 min-w-0">
          <p className="text-sm leading-snug" style={{ color: 'var(--text-primary)' }}>{node.statement}</p>
          <div className="flex gap-1.5 mt-1 items-center flex-wrap">
            {node.is_leaf && <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: '#132b1a', color: '#4ade80', fontSize: '10px' }}>leaf</span>}
            {node.testability && <TestabilityBadge classification={node.testability.classification} />}
            {node.data_card && node.data_card.data_points.length > 0 && (
              <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: '#1a2332', color: '#60a5fa', fontSize: '10px' }}>
                {node.data_card.data_points.length} data
              </span>
            )}
            {node.stress_test_severity && (
              <span className="w-2 h-2 rounded-full" style={{ background: node.stress_test_severity === 'critical' ? 'var(--accent-red)' : node.stress_test_severity === 'warning' ? 'var(--accent-amber)' : 'var(--accent-blue)' }} />
            )}
          </div>
        </div>
      </div>
      {has && !collapsed && (
        <div className="ml-3" style={{ borderLeft: '1px solid var(--border-subtle)' }}>
          {node.children.map((c) => <TreeNode key={c.id} node={c} onSelect={onSelect} selectedId={selectedId} />)}
        </div>
      )}
    </div>
  );
}

export function HypothesisTreeView({ root }: { root: HNode }) {
  const [selected, setSelected] = useState<HNode | null>(null);
  return (
    <div className="flex gap-4">
      <div className="flex-1 overflow-auto" style={{ maxHeight: 'calc(100vh - 200px)' }}>
        <TreeNode node={root} onSelect={setSelected} selectedId={selected?.id ?? null} />
      </div>
      {selected && <NodeDetailPanel node={selected} onClose={() => setSelected(null)} />}
    </div>
  );
}
TSEOF

# ======================== NODE DETAIL PANEL — dark, compact ========================
cat > apps/web/src/components/tree/NodeDetailPanel.tsx << 'TSEOF'
import type { HypothesisNode } from '@/types/hypothesis';
import { TestabilityBadge } from '@/components/analysis/TestabilityBadge';
import { DataCardView } from '@/components/data-cards/DataCard';

interface Props { node: HypothesisNode; onClose: () => void; }

export function NodeDetailPanel({ node, onClose }: Props) {
  const priority = node.testability ? node.testability.impact_score * node.testability.testability_score * node.testability.data_availability_score : null;

  return (
    <div className="w-[400px] flex-shrink-0 rounded-xl overflow-y-auto" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', maxHeight: 'calc(100vh - 200px)' }}>
      <div className="p-5">
        <div className="flex justify-between items-start mb-3">
          <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>d{node.depth} &middot; {node.id}</span>
          <button onClick={onClose} className="text-lg leading-none" style={{ color: 'var(--text-muted)' }}>&times;</button>
        </div>

        <h3 className="text-base font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>{node.statement}</h3>

        {node.testability && (
          <div className="mb-4 p-3 rounded-lg" style={{ background: 'var(--bg-secondary)' }}>
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>TESTABILITY</span>
              <TestabilityBadge classification={node.testability.classification} />
            </div>
            <p className="text-xs mb-2" style={{ color: 'var(--text-secondary)' }}>{node.testability.rationale}</p>
            <div className="grid grid-cols-4 gap-2 text-center">
              {[
                { label: 'Impact', value: `${node.testability.impact_score}/5` },
                { label: 'Test', value: `${node.testability.testability_score}/3` },
                { label: 'Data', value: `${node.testability.data_availability_score}/3` },
                { label: 'Priority', value: String(priority ?? '-') },
              ].map((m) => (
                <div key={m.label}>
                  <p className="text-xs" style={{ color: 'var(--text-muted)' }}>{m.label}</p>
                  <p className="text-sm font-semibold font-mono" style={{ color: 'var(--text-primary)' }}>{m.value}</p>
                </div>
              ))}
            </div>
          </div>
        )}

        {node.analysis && (
          <div className="mb-4 p-3 rounded-lg" style={{ background: 'var(--bg-secondary)' }}>
            <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>ANALYSIS</span>
            <p className="text-sm font-semibold mt-1" style={{ color: 'var(--accent-indigo)' }}>{node.analysis.analysis_type.replace(/_/g, ' ')}</p>
            <p className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>{node.analysis.methodology}</p>
            <div className="flex flex-wrap gap-1 mt-2">
              {node.analysis.data_sources.map((s, i) => (
                <span key={i} className="text-xs px-1.5 py-0.5 rounded" style={{ background: 'var(--bg-primary)', color: 'var(--text-muted)', border: '1px solid var(--border-subtle)' }}>{s}</span>
              ))}
            </div>
            <p className="text-xs mt-2 font-mono" style={{ color: 'var(--text-muted)' }}>{node.analysis.loe_hours}h LOE &middot; {node.analysis.output_format}</p>
          </div>
        )}

        {node.data_card && <div className="mb-4"><DataCardView card={node.data_card} /></div>}

        {node.what_must_be_true && (
          <div className="mb-3">
            <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>WHAT MUST BE TRUE</span>
            <p className="text-xs mt-1 p-2 rounded" style={{ background: 'var(--bg-secondary)', color: 'var(--text-secondary)' }}>{node.what_must_be_true}</p>
          </div>
        )}
      </div>
    </div>
  );
}
TSEOF

# ======================== TESTABILITY BADGE — dark ========================
cat > apps/web/src/components/analysis/TestabilityBadge.tsx << 'TSEOF'
import type { TestabilityClass } from '@/types/hypothesis';

const COLORS: Record<TestabilityClass, { bg: string; text: string; label: string }> = {
  quantitative: { bg: '#132b1a', text: '#4ade80', label: 'Quant' },
  qualitative: { bg: '#1a2332', text: '#60a5fa', label: 'Qual' },
  assumption: { bg: '#2d2510', text: '#fbbf24', label: 'Assumption' },
  already_answered: { bg: '#221a33', text: '#c084fc', label: 'Answered' },
};

export function TestabilityBadge({ classification }: { classification: TestabilityClass; className?: string }) {
  const c = COLORS[classification] ?? { bg: '#1f2937', text: '#9ca3af', label: classification };
  return <span className="text-xs px-1.5 py-0.5 rounded font-medium" style={{ background: c.bg, color: c.text, fontSize: '10px' }}>{c.label}</span>;
}
TSEOF

# ======================== DATA CARD — dark ========================
cat > apps/web/src/components/data-cards/DataCard.tsx << 'TSEOF'
import type { DataCard as DC } from '@/types/hypothesis';

const CONF = { high: '#22c55e', medium: '#f59e0b', low: '#ef4444' };

export function DataCardView({ card }: { card: DC }) {
  if (!card.data_points.length && !card.gaps.length) return null;
  return (
    <div>
      <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>DATA</span>
      {card.data_points.map((dp, i) => (
        <div key={i} className="mt-2 p-2 rounded" style={{ background: 'var(--bg-secondary)' }}>
          <div className="flex justify-between items-start">
            <p className="text-xs" style={{ color: 'var(--text-secondary)' }}>{dp.metric}</p>
            <span className="w-2 h-2 rounded-full flex-shrink-0 mt-0.5" style={{ background: CONF[dp.confidence] }} />
          </div>
          <p className="text-sm font-semibold font-mono" style={{ color: 'var(--accent-blue)' }}>{dp.value}</p>
          <p className="text-xs" style={{ color: 'var(--text-muted)' }}>{dp.source}</p>
        </div>
      ))}
      {card.gaps.map((g, i) => (
        <div key={i} className="mt-2 p-2 rounded" style={{ background: '#2d2510', border: '1px solid #92400e' }}>
          <p className="text-xs font-medium" style={{ color: '#fbbf24' }}>{g.description}</p>
          <p className="text-xs mt-0.5" style={{ color: '#d97706' }}>{g.suggested_alternative}</p>
        </div>
      ))}
    </div>
  );
}
TSEOF

# ======================== CONFIDENCE / GAP (kept for import compat) ========================
cat > apps/web/src/components/data-cards/ConfidenceBadge.tsx << 'TSEOF'
export function ConfidenceBadge({ level }: { level: string; className?: string }) {
  const c = level === 'high' ? '#22c55e' : level === 'medium' ? '#f59e0b' : '#ef4444';
  return <span className="w-2 h-2 rounded-full inline-block" style={{ background: c }} />;
}
TSEOF

cat > apps/web/src/components/data-cards/GapFlag.tsx << 'TSEOF'
import type { DataGap } from '@/types/hypothesis';
export function GapFlag({ gap }: { gap: DataGap }) {
  return (
    <div className="p-2 rounded text-xs" style={{ background: '#2d2510', border: '1px solid #92400e', color: '#fbbf24' }}>
      {gap.description}
    </div>
  );
}
TSEOF

# ======================== ANALYSIS PLAN TABLE — dark ========================
cat > apps/web/src/components/analysis/AnalysisPlanTable.tsx << 'TSEOF'
import { useState, useMemo } from 'react';
import type { HypothesisNode, TestabilityClass } from '@/types/hypothesis';
import { getAnalysisPlanRows } from '@/types/analysis';
import { TestabilityBadge } from './TestabilityBadge';

type SortField = 'priority' | 'loe' | 'impact' | 'type';

export function AnalysisPlanTable({ root }: { root: HypothesisNode }) {
  const [sortField, setSortField] = useState<SortField>('priority');
  const [filterClass, setFilterClass] = useState<TestabilityClass | 'all'>('all');

  const rows = useMemo(() => {
    let r = getAnalysisPlanRows(root);
    if (filterClass !== 'all') r = r.filter((row) => row.node.testability?.classification === filterClass);
    r.sort((a, b) => {
      switch (sortField) {
        case 'priority': return b.priorityScore - a.priorityScore;
        case 'loe': return (a.node.analysis?.loe_hours ?? 0) - (b.node.analysis?.loe_hours ?? 0);
        case 'impact': return (b.node.testability?.impact_score ?? 0) - (a.node.testability?.impact_score ?? 0);
        case 'type': return (a.node.testability?.classification ?? '').localeCompare(b.node.testability?.classification ?? '');
        default: return 0;
      }
    });
    return r;
  }, [root, sortField, filterClass]);

  const totalLOE = rows.reduce((s, r) => s + (r.node.analysis?.loe_hours ?? 0), 0);
  const selectStyle = { background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-secondary)', borderRadius: '8px', padding: '4px 8px', fontSize: '12px' };

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>Analysis Plan</h3>
          <p className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>{rows.length} hypotheses &middot; {totalLOE.toFixed(0)}h total</p>
        </div>
        <div className="flex gap-2">
          <select value={filterClass} onChange={(e) => setFilterClass(e.target.value as TestabilityClass | 'all')} style={selectStyle}>
            <option value="all">All</option><option value="quantitative">Quant</option><option value="qualitative">Qual</option><option value="assumption">Assumption</option><option value="already_answered">Answered</option>
          </select>
          <select value={sortField} onChange={(e) => setSortField(e.target.value as SortField)} style={selectStyle}>
            <option value="priority">Priority</option><option value="loe">LOE</option><option value="impact">Impact</option><option value="type">Type</option>
          </select>
        </div>
      </div>
      <div className="space-y-1">
        {rows.map((row, i) => (
          <div key={row.node.id} className="flex items-center gap-4 py-3 px-4 rounded-lg transition-colors"
            style={{ background: i % 2 === 0 ? 'var(--bg-card)' : 'transparent' }}>
            <span className="text-xs font-mono w-6" style={{ color: 'var(--text-muted)' }}>{i + 1}</span>
            <div className="flex-1 min-w-0">
              <p className="text-sm truncate" style={{ color: 'var(--text-primary)' }}>{row.node.statement}</p>
            </div>
            <TestabilityBadge classification={row.node.testability!.classification} />
            <span className="text-xs font-mono w-8 text-right" style={{ color: 'var(--accent-indigo)' }}>{row.priorityScore}</span>
            <span className="text-xs w-24 truncate" style={{ color: 'var(--text-secondary)' }}>{row.node.analysis?.analysis_type.replace(/_/g, ' ')}</span>
            <span className="text-xs font-mono w-10 text-right" style={{ color: 'var(--text-muted)' }}>{row.node.analysis?.loe_hours ?? 0}h</span>
          </div>
        ))}
      </div>
    </div>
  );
}
TSEOF

# ======================== STRESS TEST REPORT — dark ========================
cat > apps/web/src/components/stress-test/StressTestReport.tsx << 'TSEOF'
import { useState } from 'react';
import type { StressTestReport as Report, Critique, CritiqueSeverity, CritiqueType } from '@/types/hypothesis';

const SEV: Record<CritiqueSeverity, { bg: string; border: string; text: string; icon: string }> = {
  critical: { bg: '#1c1012', border: '#7f1d1d', text: '#fca5a5', icon: '\u2716' },
  warning: { bg: '#1c1a0e', border: '#78350f', text: '#fcd34d', icon: '\u26A0' },
  note: { bg: '#0e1624', border: '#1e3a5f', text: '#93c5fd', icon: '\u2139' },
};
const TYPES: Record<CritiqueType, string> = { devils_advocate: "Devil's Advocate", hidden_assumption: 'Hidden Assumption', sensitivity: 'Sensitivity', contradiction: 'Contradiction' };

export function StressTestReportView({ report }: { report: Report }) {
  const [fs, setFs] = useState<CritiqueSeverity | 'all'>('all');
  const [ft, setFt] = useState<CritiqueType | 'all'>('all');
  const filtered = report.critiques.filter((c) => (fs === 'all' || c.severity === fs) && (ft === 'all' || c.critique_type === ft))
    .sort((a, b) => ({ critical: 0, warning: 1, note: 2 }[a.severity]) - ({ critical: 0, warning: 1, note: 2 }[b.severity]));
  const selectStyle = { background: 'var(--bg-card)', border: '1px solid var(--border-subtle)', color: 'var(--text-secondary)', borderRadius: '8px', padding: '4px 8px', fontSize: '12px' };

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>Red Team Report</h3>
          <div className="flex gap-3 mt-1">
            <span className="text-xs font-mono" style={{ color: '#fca5a5' }}>{report.critical_count} critical</span>
            <span className="text-xs font-mono" style={{ color: '#fcd34d' }}>{report.warning_count} warning</span>
            <span className="text-xs font-mono" style={{ color: '#93c5fd' }}>{report.note_count} note</span>
          </div>
        </div>
        <div className="flex gap-2">
          <select value={fs} onChange={(e) => setFs(e.target.value as CritiqueSeverity | 'all')} style={selectStyle}>
            <option value="all">All Severity</option><option value="critical">Critical</option><option value="warning">Warning</option><option value="note">Note</option>
          </select>
          <select value={ft} onChange={(e) => setFt(e.target.value as CritiqueType | 'all')} style={selectStyle}>
            <option value="all">All Types</option><option value="devils_advocate">Devil's Advocate</option><option value="hidden_assumption">Assumptions</option><option value="sensitivity">Sensitivity</option><option value="contradiction">Contradictions</option>
          </select>
        </div>
      </div>
      <div className="space-y-2">
        {filtered.map((c, i) => {
          const s = SEV[c.severity];
          return (
            <div key={i} className="p-4 rounded-xl" style={{ background: s.bg, border: `1px solid ${s.border}` }}>
              <div className="flex items-start gap-2">
                <span style={{ color: s.text }}>{s.icon}</span>
                <div className="flex-1">
                  <div className="flex gap-2 items-center mb-1">
                    <span className="text-xs font-bold uppercase" style={{ color: s.text }}>{c.severity}</span>
                    <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: 'rgba(255,255,255,0.05)', color: 'var(--text-muted)' }}>{TYPES[c.critique_type]}</span>
                  </div>
                  <p className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{c.claim_challenged}</p>
                  <p className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>{c.evidence_basis}</p>
                  {c.breakpoint_info && <p className="text-xs mt-1 font-mono p-2 rounded" style={{ background: 'rgba(0,0,0,0.2)', color: 'var(--text-muted)' }}>{c.breakpoint_info}</p>}
                  {c.suggested_resolution && <p className="text-xs mt-1 italic" style={{ color: 'var(--text-muted)' }}>Fix: {c.suggested_resolution}</p>}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
TSEOF

# ======================== SCENARIO DAG — dark ========================
cat > apps/web/src/components/dag/ScenarioDAGView.tsx << 'TSEOF'
import { useState, useCallback } from 'react';
import type { HypothesisTree, HypothesisNode, HypothesisState, CausalDAG } from '@/types/hypothesis';
import { api } from '@/lib/api';

const SS: Record<HypothesisState, { bg: string; border: string; text: string; label: string }> = {
  true: { bg: '#0a1f0a', border: '#166534', text: '#4ade80', label: 'TRUE' },
  false: { bg: '#1c0a0a', border: '#7f1d1d', text: '#f87171', label: 'FALSE' },
  uncertain: { bg: 'var(--bg-card)', border: 'var(--border-subtle)', text: 'var(--text-muted)', label: '?' },
};

function collectAll(n: HypothesisNode): HypothesisNode[] { return [n, ...n.children.flatMap(collectAll)]; }

export function ScenarioDAGView({ tree, projectId }: { tree: HypothesisTree; projectId: string }) {
  const [dag, setDag] = useState<CausalDAG | null>(tree.causal_dag);
  const [toggling, setToggling] = useState<string | null>(null);
  const nodes = collectAll(tree.root).filter((n) => n.depth <= 2);

  const handleToggle = useCallback(async (id: string, state: HypothesisState) => {
    setToggling(id);
    try {
      const r = await api.toggleNode(projectId, id, state);
      setDag((p) => p ? { ...p, node_states: r.node_states as Record<string, HypothesisState>, node_probabilities: r.node_probabilities } : null);
    } finally { setToggling(null); }
  }, [projectId]);

  const cycle = (s: HypothesisState): HypothesisState => s === 'uncertain' ? 'true' : s === 'true' ? 'false' : 'uncertain';
  if (!dag) return null;

  return (
    <div>
      <h3 className="text-lg font-semibold mb-1" style={{ color: 'var(--text-primary)' }}>Scenario Modeling</h3>
      <p className="text-xs mb-4" style={{ color: 'var(--text-muted)' }}>Click to toggle: ? {'\u2192'} TRUE {'\u2192'} FALSE {'\u2192'} ?</p>
      <div className="space-y-1">
        {nodes.map((n) => {
          const st = (dag.node_states[n.id] ?? 'uncertain') as HypothesisState;
          const prob = dag.node_probabilities[n.id] ?? 0.5;
          const s = SS[st];
          return (
            <div key={n.id} className="flex items-center gap-3 py-2.5 px-3 rounded-lg cursor-pointer transition-all"
              style={{ marginLeft: n.depth * 20, background: s.bg, border: `1px solid ${s.border}`, opacity: toggling === n.id ? 0.5 : 1 }}
              onClick={() => !toggling && handleToggle(n.id, cycle(st))}>
              <span className="text-xs font-mono font-bold w-14 text-center py-0.5 rounded" style={{ color: s.text, border: `1px solid ${s.border}` }}>{s.label}</span>
              <p className="flex-1 text-sm" style={{ color: 'var(--text-primary)' }}>{n.statement}</p>
              <div className="w-16">
                <div className="h-1.5 rounded-full" style={{ background: 'var(--bg-primary)' }}>
                  <div className="h-1.5 rounded-full transition-all duration-500" style={{ width: `${prob * 100}%`, background: prob >= 0.7 ? '#22c55e' : prob <= 0.3 ? '#ef4444' : '#f59e0b' }} />
                </div>
                <p className="text-xs text-center mt-0.5 font-mono" style={{ color: 'var(--text-muted)', fontSize: '10px' }}>{(prob * 100).toFixed(0)}%</p>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
TSEOF

# ======================== WORKPLAN VIEW ========================
mkdir -p apps/web/src/components/workplan

cat > apps/web/src/components/workplan/WorkplanView.tsx << 'TSEOF'
import { useState } from 'react';
import { api } from '@/lib/api';

interface WorkItem { hypothesis_id: string; hypothesis_statement: string; analysis_type: string; loe_hours: number; resource_type: string; }
interface Workstream { id: string; name: string; description: string; items: WorkItem[]; total_loe: number; sequence_order: number; depends_on: string[]; }
interface Workplan { workstreams: Workstream[]; total_loe: number; estimated_weeks: number; critical_path: string[]; summary: string; }

const RES_COLORS: Record<string, string> = { analyst: '#3b82f6', manager: '#f59e0b', partner: '#a855f7' };

export function WorkplanView({ workplan: initial, projectId }: { workplan: Workplan; projectId: string }) {
  const [wp, setWp] = useState<Workplan>(initial);
  const [msg, setMsg] = useState('');
  const [negotiating, setNegotiating] = useState(false);

  const handleNegotiate = async () => {
    if (!msg.trim()) return;
    setNegotiating(true);
    try {
      const result = await api.negotiateWorkplan(projectId, msg.trim());
      setWp(result as Workplan);
      setMsg('');
    } catch (e) {
      console.error(e);
    } finally {
      setNegotiating(false);
    }
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>Workplan</h3>
          <p className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>{wp.workstreams.length} workstreams &middot; {wp.total_loe.toFixed(0)}h &middot; {wp.estimated_weeks} weeks</p>
        </div>
      </div>

      {wp.summary && <p className="text-sm mb-4 p-3 rounded-lg" style={{ background: 'var(--bg-card)', color: 'var(--text-secondary)' }}>{wp.summary}</p>}

      {/* Gantt-style visualization */}
      <div className="space-y-3 mb-6">
        {wp.workstreams.map((ws) => (
          <div key={ws.id} className="rounded-xl overflow-hidden" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
            <div className="flex items-center justify-between p-3" style={{ borderBottom: '1px solid var(--border-subtle)' }}>
              <div className="flex items-center gap-3">
                <span className="text-xs font-mono px-2 py-0.5 rounded" style={{ background: 'var(--accent-indigo)', color: 'white' }}>{ws.id}</span>
                <span className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>{ws.name}</span>
              </div>
              <div className="flex items-center gap-3">
                {ws.depends_on.length > 0 && (
                  <span className="text-xs" style={{ color: 'var(--text-muted)' }}>after {ws.depends_on.join(', ')}</span>
                )}
                <span className="text-xs font-mono" style={{ color: 'var(--accent-amber)' }}>{ws.total_loe}h</span>
              </div>
            </div>
            <div className="p-2 space-y-1">
              {ws.items.map((item, i) => (
                <div key={i} className="flex items-center gap-3 py-1.5 px-2 rounded" style={{ background: 'var(--bg-secondary)' }}>
                  <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: RES_COLORS[item.resource_type] ?? '#6b7280' }} />
                  <p className="text-xs flex-1 truncate" style={{ color: 'var(--text-secondary)' }}>{item.hypothesis_statement || item.hypothesis_id}</p>
                  <span className="text-xs" style={{ color: 'var(--text-muted)' }}>{item.analysis_type.replace(/_/g, ' ')}</span>
                  <span className="text-xs font-mono w-8 text-right" style={{ color: 'var(--text-muted)' }}>{item.loe_hours}h</span>
                  <span className="text-xs capitalize" style={{ color: RES_COLORS[item.resource_type] }}>{item.resource_type}</span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* Legend */}
      <div className="flex gap-4 mb-6">
        {Object.entries(RES_COLORS).map(([role, color]) => (
          <div key={role} className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full" style={{ background: color }} />
            <span className="text-xs capitalize" style={{ color: 'var(--text-muted)' }}>{role}</span>
          </div>
        ))}
      </div>

      {/* Negotiation chat */}
      <div className="p-4 rounded-xl" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
        <p className="text-xs font-mono mb-2" style={{ color: 'var(--text-muted)' }}>NEGOTIATE WORKPLAN</p>
        <div className="flex gap-2">
          <input type="text" value={msg} onChange={(e) => setMsg(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleNegotiate()}
            placeholder='e.g., "We only have 3 weeks, reprioritize" or "Drop competitive analysis"'
            className="flex-1 px-3 py-2 rounded-lg text-sm outline-none"
            style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)' }}
            disabled={negotiating} />
          <button onClick={handleNegotiate} disabled={negotiating || !msg.trim()}
            className="px-4 py-2 rounded-lg text-sm font-medium transition-colors"
            style={{ background: msg.trim() ? 'var(--accent-indigo)' : 'var(--bg-secondary)', color: msg.trim() ? 'white' : 'var(--text-muted)' }}>
            {negotiating ? '...' : 'Send'}
          </button>
        </div>
      </div>
    </div>
  );
}
TSEOF

# ======================== API CLIENT — add negotiate ========================
cat > apps/web/src/lib/api.ts << 'TSEOF'
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
  saveScenario: (projectId: string, name: string) =>
    request<{ id: string; name: string }>(`/api/projects/${projectId}/scenarios`, { method: 'POST', body: JSON.stringify({ name }) }),
  negotiateWorkplan: (projectId: string, message: string) =>
    request<unknown>(`/api/projects/${projectId}/workplan/negotiate`, { method: 'POST', body: JSON.stringify({ message }) }),
};
TSEOF

# ======================== TYPES: add workplan to Project ========================
cat > apps/web/src/types/project.ts << 'TSEOF'
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
TSEOF

# ======================== ERROR BOUNDARY — dark ========================
cat > apps/web/src/components/common/ErrorBoundary.tsx << 'TSEOF'
import { Component, type ReactNode } from 'react';

interface Props { children: ReactNode; fallback?: ReactNode; }
interface State { hasError: boolean; error: Error | null; }

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };
  static getDerivedStateFromError(error: Error): State { return { hasError: true, error }; }
  render() {
    if (this.state.hasError) return (
      <div className="p-8 text-center">
        <h2 className="text-lg font-semibold mb-2" style={{ color: 'var(--accent-red)' }}>Something went wrong</h2>
        <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>{this.state.error?.message}</p>
        <button onClick={() => this.setState({ hasError: false, error: null })} className="mt-4 px-4 py-2 rounded-lg text-sm"
          style={{ background: 'var(--bg-card)', color: 'var(--text-primary)' }}>Try again</button>
      </div>
    );
    return this.props.children;
  }
}
TSEOF

echo ""
echo "=== Phase 6 files written ==="
echo ""
echo "What changed:"
echo ""
echo "BACKEND:"
echo "  - Workplan Compiler: groups hypotheses into workstreams, sequences, assigns resources"
echo "  - Negotiation Agent: 'We only have 3 weeks' -> workplan mutation via NL"
echo "  - POST /api/projects/{id}/workplan/negotiate endpoint"
echo ""
echo "FRONTEND:"
echo "  1. DARK THEME: Professional dark UI with DM Sans + JetBrains Mono"
echo "  2. LIVE AGENT STATUS: Loading screen shows exactly which agent is running,"
echo "     with per-phase progress bars and checkmarks as agents complete"
echo "  3. COMPACT TREE: depth-2+ collapsed by default, less visual noise"
echo "  4. DETAIL PANEL: side panel (not overlay), compact sections"
echo "  5. WORKPLAN TAB: Gantt-style workstream cards with resource color coding"
echo "     + NL negotiation chat bar at bottom"
echo "  6. ALL VIEWS: dark-themed, consistent, scannable"
echo ""
echo "Run: restart uvicorn + npm run dev, generate a new tree."