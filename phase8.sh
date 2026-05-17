#!/bin/bash
set -e

# ============================================================
# HypoTree Phase 8 — Episodic Memory + Human-Readable Live Feed
# Run from hypotree/ root
# Usage: bash phase8.sh
# ============================================================

echo "=== Phase 8: Episodic Memory + Readable Live Feed ==="

# ======================== EPISODIC MEMORY STORE (SQLite, no Neo4j) ========================
mkdir -p packages/agents/memory

cat > packages/agents/memory/__init__.py << 'PYEOF'
PYEOF

cat > packages/agents/memory/store.py << 'PYEOF'
"""Episodic memory — stores completed trees for retrieval and learning."""
from __future__ import annotations

import json
import logging
import os
import sqlite3
from datetime import datetime
from typing import Optional

logger = logging.getLogger(__name__)

DB_PATH = os.environ.get("HYPOTREE_MEMORY_DB", os.path.join(os.path.dirname(__file__), "..", "..", "..", "hypotree_memory.db"))


def _get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""CREATE TABLE IF NOT EXISTS cases (
        id TEXT PRIMARY KEY,
        industry TEXT,
        company TEXT,
        question TEXT,
        question_type TEXT,
        framework TEXT,
        tree_json TEXT,
        feedback_json TEXT DEFAULT '{}',
        node_count INTEGER DEFAULT 0,
        leaf_count INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS feedback (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        case_id TEXT,
        node_id TEXT,
        outcome TEXT,
        notes TEXT,
        created_at TEXT,
        FOREIGN KEY (case_id) REFERENCES cases(id)
    )""")
    conn.commit()
    return conn


def save_case(case_id: str, industry: str, company: str, question: str,
              question_type: str, framework: str, tree_json: str,
              node_count: int, leaf_count: int) -> None:
    conn = _get_conn()
    now = datetime.utcnow().isoformat()
    conn.execute(
        """INSERT OR REPLACE INTO cases (id, industry, company, question, question_type, framework, tree_json, node_count, leaf_count, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (case_id, industry, company, question, question_type, framework, tree_json, node_count, leaf_count, now, now)
    )
    conn.commit()
    conn.close()
    logger.info("Saved case %s to memory (%d nodes)", case_id, node_count)


def find_similar_cases(question_type: str, industry: str = "", limit: int = 5) -> list[dict]:
    conn = _get_conn()
    cursor = conn.execute(
        """SELECT id, industry, company, question, question_type, framework, node_count, leaf_count, created_at
           FROM cases
           WHERE question_type = ? OR industry LIKE ?
           ORDER BY created_at DESC
           LIMIT ?""",
        (question_type, f"%{industry}%", limit)
    )
    results = []
    for row in cursor.fetchall():
        results.append({
            "id": row[0], "industry": row[1], "company": row[2], "question": row[3],
            "question_type": row[4], "framework": row[5], "node_count": row[6],
            "leaf_count": row[7], "created_at": row[8],
        })
    conn.close()
    return results


def get_case_tree(case_id: str) -> Optional[str]:
    conn = _get_conn()
    cursor = conn.execute("SELECT tree_json FROM cases WHERE id = ?", (case_id,))
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else None


def save_feedback(case_id: str, node_id: str, outcome: str, notes: str = "") -> None:
    conn = _get_conn()
    now = datetime.utcnow().isoformat()
    conn.execute(
        "INSERT INTO feedback (case_id, node_id, outcome, notes, created_at) VALUES (?, ?, ?, ?, ?)",
        (case_id, node_id, outcome, notes, now)
    )
    conn.commit()
    conn.close()


def get_case_feedback(case_id: str) -> list[dict]:
    conn = _get_conn()
    cursor = conn.execute(
        "SELECT node_id, outcome, notes, created_at FROM feedback WHERE case_id = ? ORDER BY created_at",
        (case_id,)
    )
    results = [{"node_id": r[0], "outcome": r[1], "notes": r[2], "created_at": r[3]} for r in cursor.fetchall()]
    conn.close()
    return results


def list_all_cases(limit: int = 20) -> list[dict]:
    conn = _get_conn()
    cursor = conn.execute(
        "SELECT id, industry, company, question, question_type, framework, node_count, leaf_count, created_at FROM cases ORDER BY created_at DESC LIMIT ?",
        (limit,)
    )
    results = [{"id": r[0], "industry": r[1], "company": r[2], "question": r[3], "question_type": r[4],
                "framework": r[5], "node_count": r[6], "leaf_count": r[7], "created_at": r[8]} for r in cursor.fetchall()]
    conn.close()
    return results
PYEOF

# ======================== UPDATE ORCHESTRATOR — save to memory ========================
cat > packages/agents/orchestrator/agent.py << 'PYEOF'
"""Orchestrator agent — full pipeline through Phase 8."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent, _emit, set_current_project
from packages.agents.decomposer.agent import DecomposerAgent
from packages.agents.mece_validator.agent import MECEValidatorAgent
from packages.agents.testability_classifier.agent import TestabilityClassifierAgent
from packages.agents.analysis_designer.agent import AnalysisDesignerAgent
from packages.agents.data_retrieval.agent import DataRetrievalAgent
from packages.agents.red_team.agent import RedTeamAgent
from packages.agents.graph.builder import DAGBuilderAgent
from packages.agents.workplan.agent import WorkplanAgent
from packages.agents.memory.store import save_case, find_similar_cases
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
        _emit("P1", "Orchestrator", "Identifying question type and selecting framework")
        prompt = CLASSIFICATION_PROMPT.format(industry=industry, company=company, question=question)
        return ClassificationResult(**json.loads(self.call_llm(prompt)))

    def generate_root_and_branches(self, industry, company, question, classification):
        _emit("P1", "Orchestrator", f"Building root hypothesis using {classification.framework.value.replace('_', ' ')} framework")
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
        _emit("P1", "Orchestrator", f"Created {len(root.children)} top-level hypothesis branches")
        return root

    def _decompose_with_validation(self, node, industry, company, question):
        _emit("P1", "Decomposer", f"Breaking down: \"{node.statement[:60]}...\"")
        children = self.decomposer.decompose(parent=node, industry=industry, company=company, question=question)
        best_children, best_score = children, 999
        for attempt in range(MECE_MAX_RETRIES):
            _emit("P1", "MECE Validator", f"Checking {len(children)} sub-hypotheses for overlaps and gaps")
            validation = self.mece_validator.validate(parent=node, children=children)
            score = len(validation.overlaps) + len(validation.gaps)
            if score < best_score: best_score, best_children = score, children
            if validation.is_valid:
                _emit("P1", "MECE Validator", f"Validated: {len(children)} sub-hypotheses are mutually exclusive and collectively exhaustive")
                return children
            if attempt < MECE_MAX_RETRIES - 1:
                _emit("P1", "Decomposer", f"Refining decomposition (found {len(validation.overlaps)} overlaps, {len(validation.gaps)} gaps)")
                children = self.decomposer.decompose(parent=node, industry=industry, company=company, question=question, previous_issues=validation)
        _emit("P1", "MECE Validator", f"Accepted best decomposition after {MECE_MAX_RETRIES} attempts", "warning")
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
        _emit("P2", "Classifier", f"{node.testability.classification.value.replace('_', ' ').title()} (priority {node.testability.priority_score:.0f}): \"{node.statement[:50]}...\"")
        if node.testability.classification != TestabilityClass.ASSUMPTION or node.testability.impact_score >= 4:
            node.analysis = self.analysis_designer.design(node=node, testability=node.testability, industry=industry, company=company, question=question)
            _emit("P2", "Analysis Designer", f"Proposed {node.analysis.analysis_type.value.replace('_', ' ')} ({node.analysis.loe_hours:.0f}h)")

    def generate_tree(self, industry: str, company: str, question: str, project_id: str = "") -> HypothesisTree:
        if project_id:
            set_current_project(project_id)

        # Check episodic memory for similar past cases
        _emit("P1", "Memory", "Searching for similar past analyses...")
        try:
            # We need to classify first to search by type
            classification = self.classify_question(industry, company, question)
            similar = find_similar_cases(classification.question_type.value, industry)
            if similar:
                _emit("P1", "Memory", f"Found {len(similar)} similar past cases for reference")
                for s in similar[:2]:
                    _emit("P1", "Memory", f"  Previous: \"{s['question'][:60]}...\" ({s['industry']})")
            else:
                _emit("P1", "Memory", "No similar past cases found. Starting fresh.")
        except Exception:
            classification = self.classify_question(industry, company, question)

        _emit("P1", "Orchestrator", f"Question type: {classification.question_type.value.replace('_', ' ').title()} (confidence: {classification.confidence:.0%})")

        root = self.generate_root_and_branches(industry, company, question, classification)
        _emit("P1", "Orchestrator", "Recursively decomposing each branch to depth 3...")
        self._decompose_recursive(root, industry, company, question, TARGET_TREE_DEPTH)
        all_nodes = self._collect_all(root)
        leaves = [n for n in all_nodes if n.is_leaf]
        _emit("P1", "Orchestrator", f"Hypothesis tree complete: {len(all_nodes)} nodes, {len(leaves)} testable leaves")

        _emit("P2", "Orchestrator", f"Classifying testability and designing analyses for {len(leaves)} leaves...")
        self._classify_and_design(root, industry, company, question)
        _emit("P2", "Orchestrator", "All leaves classified with proposed analysis methodologies")

        _emit("P3", "Data Retrieval", "Searching Yahoo Finance and SEC EDGAR for real financial data...")
        self.data_retrieval.retrieve_for_tree(root, industry, company, question)
        data_count = len([n for n in all_nodes if n.data_card and n.data_card.data_points])
        gap_count = sum(len(n.data_card.gaps) for n in all_nodes if n.data_card)
        _emit("P3", "Data Retrieval", f"Retrieved data for {data_count} hypotheses. Flagged {gap_count} data gaps.")

        tree = HypothesisTree(root=root, classification=classification, industry=industry, company=company, question=question)

        _emit("P4", "Red Team", "Launching adversarial stress-test on the hypothesis tree...")
        tree.stress_test_report = self.red_team.stress_test(tree)
        sr = tree.stress_test_report
        _emit("P4", "Red Team", f"Stress test found {sr.critical_count} critical issues, {sr.warning_count} warnings, {sr.note_count} notes")

        _emit("P5", "DAG Builder", "Analyzing causal dependencies between hypotheses...")
        tree.causal_dag = self.dag_builder.build_dag(root)
        _emit("P5", "DAG Builder", f"Built dependency graph with {len(tree.causal_dag.edges)} causal relationships")

        _emit("P6", "Workplan", "Grouping hypotheses into workstreams and sequencing...")
        workplan = self.workplan_agent.compile_workplan(root, industry, company, question)
        tree.workplan = workplan.model_dump()
        _emit("P6", "Workplan", f"Workplan: {len(workplan.workstreams)} workstreams, {workplan.total_loe:.0f} analyst-hours, {workplan.estimated_weeks:.0f} weeks")

        # Save to episodic memory
        _emit("P8", "Memory", "Saving this analysis to institutional memory...")
        try:
            tree_json = tree.model_dump_json()
            save_case(
                case_id=tree.id, industry=industry, company=company, question=question,
                question_type=classification.question_type.value,
                framework=classification.framework.value,
                tree_json=tree_json, node_count=len(all_nodes), leaf_count=len(leaves),
            )
            _emit("P8", "Memory", "Analysis saved. Future similar questions will reference this case.")
        except Exception as e:
            _emit("P8", "Memory", f"Could not save to memory: {e}", "warning")

        _emit("done", "Orchestrator", "Analysis complete. All phases finished successfully.")
        return tree

    @staticmethod
    def _collect_all(node):
        result = [node]
        for child in node.children: result.extend(OrchestratorAgent._collect_all(child))
        return result
PYEOF

# ======================== MEMORY API ENDPOINTS ========================
cat > apps/api/app/routers/trees.py << 'PYEOF'
"""Tree, DAG, workplan, and memory endpoints."""
from __future__ import annotations

import json
import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from packages.agents.graph.state import propagate_states
from packages.agents.workplan.agent import WorkplanAgent
from packages.agents.workplan.schemas import Workplan
from packages.agents.memory.store import list_all_cases, get_case_feedback, save_feedback, find_similar_cases
from packages.shared.types import HypothesisState, ScenarioConfig

logger = logging.getLogger(__name__)
router = APIRouter(tags=["trees"])

from app.routers.projects import _projects


class ToggleRequest(BaseModel):
    node_id: str
    state: HypothesisState

class NegotiateRequest(BaseModel):
    message: str

class FeedbackRequest(BaseModel):
    node_id: str
    outcome: str  # correct, incorrect, irrelevant, missing
    notes: str = ""


@router.post("/projects/{project_id}/dag/toggle")
async def toggle_node(project_id: str, body: ToggleRequest):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404, "Project not found")
    tree = project.get("tree")
    if not tree or not tree.causal_dag: raise HTTPException(400, "No DAG")
    dag = propagate_states(tree.causal_dag, body.node_id, body.state)
    tree.causal_dag = dag
    return {"node_states": {k: v.value for k, v in dag.node_states.items()}, "node_probabilities": dag.node_probabilities}


@router.post("/projects/{project_id}/workplan/negotiate")
async def negotiate_workplan(project_id: str, body: NegotiateRequest):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    tree = project.get("tree")
    if not tree or not tree.workplan: raise HTTPException(400)
    agent = WorkplanAgent()
    updated = agent.negotiate(Workplan(**tree.workplan), body.message)
    tree.workplan = updated.model_dump()
    return updated.model_dump()


@router.post("/projects/{project_id}/feedback")
async def submit_feedback(project_id: str, body: FeedbackRequest):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    tree = project.get("tree")
    if not tree: raise HTTPException(400)
    save_feedback(tree.id, body.node_id, body.outcome, body.notes)
    return {"status": "saved"}


@router.get("/projects/{project_id}/feedback")
async def get_feedback(project_id: str):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    tree = project.get("tree")
    if not tree: raise HTTPException(400)
    return get_case_feedback(tree.id)


@router.get("/memory/cases")
async def list_cases():
    return list_all_cases()


@router.get("/memory/similar")
async def similar_cases(question_type: str = "", industry: str = ""):
    return find_similar_cases(question_type, industry)
PYEOF

# ======================== HUMAN-READABLE LIVE STATUS FEED ========================
cat > apps/web/src/components/common/LiveAgentStatus.tsx << 'TSEOF'
import { useState, useEffect, useRef } from 'react';

interface LogEntry {
  ts: number;
  phase: string;
  agent: string;
  message: string;
  level: string;
}

const PHASE_META: Record<string, { label: string; color: string; icon: string; description: string }> = {
  P1: { label: 'Building Hypothesis Tree', color: '#6366f1', icon: '\u{1F333}', description: 'Decomposing the strategic question into a structured MECE tree' },
  P2: { label: 'Classifying & Designing', color: '#3b82f6', icon: '\u{1F4CA}', description: 'Determining how each hypothesis can be tested and what analysis to run' },
  P3: { label: 'Gathering Real Data', color: '#22c55e', icon: '\u{1F4E1}', description: 'Pulling financial data from Yahoo Finance, SEC filings, and public sources' },
  P4: { label: 'Stress-Testing', color: '#ef4444', icon: '\u{1F6E1}', description: 'An adversarial agent is challenging assumptions and finding contradictions' },
  P5: { label: 'Mapping Dependencies', color: '#a855f7', icon: '\u{1F517}', description: 'Identifying which hypotheses depend on each other for scenario modeling' },
  P6: { label: 'Building Workplan', color: '#f59e0b', icon: '\u{1F4CB}', description: 'Grouping analyses into workstreams with timelines and resource assignments' },
  P8: { label: 'Saving to Memory', color: '#14b8a6', icon: '\u{1F4BE}', description: 'Storing this analysis for institutional learning on future questions' },
  done: { label: 'Complete', color: '#22c55e', icon: '\u2713', description: 'All phases finished' },
};

interface Props {
  projectId: string | null;
  onComplete: () => void;
}

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
      } catch (e) { /* keepalive */ }
    };
    es.onerror = () => { setTimeout(onComplete, 3000); };
    return () => es.close();
  }, [projectId, onComplete]);

  useEffect(() => {
    feedRef.current?.scrollTo({ top: feedRef.current.scrollHeight, behavior: 'smooth' });
  }, [logs]);

  const formatTime = (s: number) => `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, '0')}`;
  const meta = PHASE_META[currentPhase] || PHASE_META.P1;
  const phases = ['P1', 'P2', 'P3', 'P4', 'P5', 'P6'];
  const completedPhases = new Set(logs.filter(l => l.message.includes('complete') || l.message.includes('Complete')).map(l => l.phase));

  // Group logs into meaningful events (skip noisy token counts)
  const visibleLogs = logs.filter(l =>
    !l.message.includes('tokens_in=') &&
    l.message.length > 0 &&
    l.phase !== ''
  );

  return (
    <div className="max-w-3xl mx-auto py-12">
      {/* Current phase hero */}
      <div className="text-center mb-8">
        <div className="inline-flex items-center gap-3 px-5 py-2.5 rounded-2xl mb-4"
          style={{ background: meta.color + '15', border: `1px solid ${meta.color}33` }}>
          <span className="text-2xl">{meta.icon}</span>
          <span className="text-sm font-semibold" style={{ color: meta.color }}>{meta.label}</span>
          <span className="text-xs font-mono px-2 py-0.5 rounded-full" style={{ background: 'var(--bg-primary)', color: 'var(--text-muted)' }}>{formatTime(elapsed)}</span>
        </div>
        <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>{meta.description}</p>
      </div>

      {/* Phase steps */}
      <div className="flex justify-center gap-2 mb-8">
        {phases.map((p) => {
          const pm = PHASE_META[p];
          const done = completedPhases.has(p) || phases.indexOf(p) < phases.indexOf(currentPhase);
          const active = p === currentPhase;
          return (
            <div key={p} className="flex flex-col items-center gap-1.5">
              <div className="w-10 h-10 rounded-xl flex items-center justify-center text-lg transition-all duration-500"
                style={{
                  background: done ? pm.color + '22' : active ? pm.color + '15' : 'var(--bg-card)',
                  border: `2px solid ${active ? pm.color : done ? pm.color + '44' : 'var(--border-subtle)'}`,
                }}>
                {done ? <span style={{ color: pm.color }}>{'\u2713'}</span> : <span>{pm.icon}</span>}
              </div>
              <span className="text-xs" style={{ color: active ? pm.color : 'var(--text-muted)', fontWeight: active ? 600 : 400 }}>
                {pm.label.split(' ')[0]}
              </span>
            </div>
          );
        })}
      </div>

      {/* Activity feed */}
      <div className="rounded-2xl overflow-hidden" style={{ background: 'var(--bg-card)', border: '1px solid var(--border-subtle)' }}>
        <div className="px-5 py-3 flex items-center justify-between" style={{ borderBottom: '1px solid var(--border-subtle)' }}>
          <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>Activity</span>
          <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>{visibleLogs.length} events</span>
        </div>

        <div ref={feedRef} className="px-5 py-3 overflow-y-auto" style={{ maxHeight: '50vh', minHeight: '250px' }}>
          {visibleLogs.map((entry, i) => {
            const pm = PHASE_META[entry.phase] || { color: '#6b7280', icon: '\u25CB' };
            const isWarning = entry.level === 'warning';
            const isRecent = i >= visibleLogs.length - 3;

            return (
              <div key={i} className="flex gap-3 py-2.5 transition-opacity duration-500"
                style={{ opacity: isRecent ? 1 : 0.6 }}>
                {/* Timeline dot */}
                <div className="flex flex-col items-center flex-shrink-0" style={{ width: '20px' }}>
                  <div className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{
                    background: pm.color,
                    boxShadow: isRecent ? `0 0 8px ${pm.color}44` : 'none'
                  }} />
                  {i < visibleLogs.length - 1 && <div className="w-px flex-1 mt-1" style={{ background: 'var(--border-subtle)' }} />}
                </div>

                <div className="flex-1 min-w-0 pb-1">
                  <div className="flex items-center gap-2 mb-0.5">
                    <span className="text-xs font-semibold" style={{ color: pm.color }}>{entry.agent}</span>
                    {isWarning && <span className="text-xs px-1.5 rounded" style={{ background: '#2d2510', color: '#fbbf24' }}>attention</span>}
                  </div>
                  <p className="text-sm leading-relaxed" style={{ color: isWarning ? '#fbbf24' : 'var(--text-secondary)' }}>
                    {entry.message}
                  </p>
                </div>
              </div>
            );
          })}

          {/* Pulsing indicator */}
          <div className="flex gap-3 py-2">
            <div className="flex flex-col items-center" style={{ width: '20px' }}>
              <div className="w-2.5 h-2.5 rounded-full animate-pulse" style={{ background: meta.color }} />
            </div>
            <span className="text-sm animate-pulse" style={{ color: 'var(--text-muted)' }}>Working...</span>
          </div>
        </div>
      </div>
    </div>
  );
}
TSEOF

# ======================== PAST CASES BROWSER (shown on landing page) ========================
mkdir -p apps/web/src/components/memory

cat > apps/web/src/components/memory/PastCases.tsx << 'TSEOF'
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
TSEOF

# ======================== UPDATE QUESTION INPUT — add past cases ========================
cat > apps/web/src/components/forms/QuestionInput.tsx << 'TSEOF'
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
TSEOF

echo ""
echo "=== Phase 8 files written ==="
echo ""
echo "What changed:"
echo ""
echo "BACKEND:"
echo "  - Episodic memory via SQLite (no Neo4j dependency)"
echo "  - Every completed analysis saved to hypotree_memory.db"
echo "  - Similar past cases retrieved at start of each new analysis"
echo "  - POST /api/projects/{id}/feedback — mark hypotheses correct/incorrect/irrelevant/missing"
echo "  - GET /api/memory/cases — list all past analyses"
echo "  - GET /api/memory/similar — find similar cases by type/industry"
echo ""
echo "FRONTEND:"
echo "  - Live status feed is now HUMAN-READABLE:"
echo "    - No raw token counts or technical jargon"
echo "    - Messages like 'Breaking down: \"Revenue synergies...\"'"
echo "    - 'Checking 3 sub-hypotheses for overlaps and gaps'"
echo "    - 'Stress test found 5 critical issues, 12 warnings'"
echo "    - Timeline dots with phase colors, recent items highlighted"
echo "    - Phase step icons at top showing progress"
echo "  - Landing page shows PAST ANALYSES section"
echo "  - Each past analysis shows question, industry, company, node count, date"
echo ""
echo "Run: restart uvicorn + npm run dev, generate a tree."
echo "Watch the human-readable activity feed. Run a second query and see past cases appear."