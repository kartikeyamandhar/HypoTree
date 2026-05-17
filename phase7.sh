#!/bin/bash
set -e

# ============================================================
# HypoTree Phase 7 — Multi-Modal Ingestion + Benchmarking + Live Terminal
# Run from hypotree/ root
# Usage: bash phase7.sh
# ============================================================

echo "=== Phase 7: Multi-Modal Ingestion + Benchmarking + Live Terminal ==="

# ======================== SSE LOG STREAMING INFRASTRUCTURE ========================
cat > apps/api/app/services/orchestrator.py << 'PYEOF'
"""Real-time log streaming via Server-Sent Events."""
from __future__ import annotations

import asyncio
import time
import logging
from collections import defaultdict
from typing import Optional

logger = logging.getLogger(__name__)

_streams: dict[str, asyncio.Queue] = {}
_logs: dict[str, list[dict]] = defaultdict(list)


def get_or_create_queue(project_id: str) -> asyncio.Queue:
    if project_id not in _streams:
        _streams[project_id] = asyncio.Queue()
    return _streams[project_id]


def push_log(project_id: str, phase: str, agent: str, message: str, level: str = "info"):
    entry = {
        "ts": time.time(),
        "phase": phase,
        "agent": agent,
        "message": message,
        "level": level,
    }
    _logs[project_id].append(entry)
    q = _streams.get(project_id)
    if q:
        try:
            q.put_nowait(entry)
        except asyncio.QueueFull:
            pass


def get_logs(project_id: str) -> list[dict]:
    return _logs.get(project_id, [])


def clear_logs(project_id: str):
    _logs.pop(project_id, None)
    _streams.pop(project_id, None)
PYEOF

# ======================== PATCH BASE AGENT — emit logs to SSE ========================
cat > packages/agents/base.py << 'PYEOF'
"""Base class for all HypoTree agents."""
from __future__ import annotations

import logging
import os
import time
from abc import ABC, abstractmethod
from typing import TypeVar

import anthropic
from dotenv import load_dotenv

from packages.shared.constants import DEFAULT_MODEL, LLM_MAX_RETRIES

load_dotenv(os.path.join(os.path.dirname(__file__), "..", "..", "apps", "api", ".env"))
load_dotenv()

logger = logging.getLogger(__name__)
T = TypeVar("T")

# Global project_id for log routing (set by orchestrator before generation)
_current_project_id: str | None = None


def set_current_project(pid: str):
    global _current_project_id
    _current_project_id = pid


def _emit(phase: str, agent: str, message: str, level: str = "info"):
    """Emit log to both Python logger and SSE stream."""
    getattr(logger, level)(message)
    if _current_project_id:
        try:
            from app.services.orchestrator import push_log
            push_log(_current_project_id, phase, agent, message, level)
        except Exception:
            pass


class BaseAgent(ABC):
    def __init__(self, model: str = DEFAULT_MODEL):
        self.model = model
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if not api_key:
            raise RuntimeError("ANTHROPIC_API_KEY not set.")
        self.client = anthropic.Anthropic(api_key=api_key)

    @abstractmethod
    def get_system_prompt(self) -> str: ...

    def call_llm(self, user_prompt: str, system_prompt: str | None = None) -> str:
        sys = system_prompt or self.get_system_prompt()
        last_error: Exception | None = None
        agent_name = self.__class__.__name__

        for attempt in range(LLM_MAX_RETRIES):
            try:
                start = time.time()
                response = self.client.messages.create(
                    model=self.model, max_tokens=4096, system=sys,
                    messages=[{"role": "user", "content": user_prompt}],
                )
                elapsed = time.time() - start
                text = response.content[0].text
                _emit("", agent_name,
                    f"tokens_in={response.usage.input_tokens} tokens_out={response.usage.output_tokens} latency={elapsed:.1f}s")
                return text
            except Exception as e:
                last_error = e
                _emit("", agent_name, f"attempt {attempt+1} failed: {e}", "warning")

        raise RuntimeError(f"{agent_name} failed after {LLM_MAX_RETRIES} attempts: {last_error}")
PYEOF

# ======================== UPDATE ORCHESTRATOR — emit phase logs ========================
cat > packages/agents/orchestrator/agent.py << 'PYEOF'
"""Orchestrator agent — full pipeline through Phase 7."""
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
        _emit("P1", "Orchestrator", f"Classifying: {question[:60]}...")
        prompt = CLASSIFICATION_PROMPT.format(industry=industry, company=company, question=question)
        return ClassificationResult(**json.loads(self.call_llm(prompt)))

    def generate_root_and_branches(self, industry, company, question, classification):
        _emit("P1", "Orchestrator", f"Generating root + branches ({classification.framework.value})")
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
        _emit("P1", "Orchestrator", f"Root generated with {len(root.children)} branches")
        return root

    def _decompose_with_validation(self, node, industry, company, question):
        _emit("P1", "Decomposer", f"Decomposing: {node.statement[:50]}...")
        children = self.decomposer.decompose(parent=node, industry=industry, company=company, question=question)
        best_children, best_score = children, 999
        for attempt in range(MECE_MAX_RETRIES):
            _emit("P1", "MECE Validator", f"Validating {len(children)} siblings (attempt {attempt+1})")
            validation = self.mece_validator.validate(parent=node, children=children)
            score = len(validation.overlaps) + len(validation.gaps)
            if score < best_score: best_score, best_children = score, children
            if validation.is_valid:
                _emit("P1", "MECE Validator", f"PASSED - {len(children)} children accepted")
                return children
            if attempt < MECE_MAX_RETRIES - 1:
                children = self.decomposer.decompose(parent=node, industry=industry, company=company, question=question, previous_issues=validation)
        _emit("P1", "MECE Validator", f"Exhausted retries, accepting best (score={best_score})", "warning")
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
        _emit("P2", "Testability Classifier", f"Classifying: {node.statement[:50]}...")
        node.testability = self.testability_classifier.classify(node=node, industry=industry, company=company, question=question)
        _emit("P2", "Testability Classifier", f"=> {node.testability.classification.value} (priority={node.testability.priority_score:.0f})")
        if node.testability.classification != TestabilityClass.ASSUMPTION or node.testability.impact_score >= 4:
            _emit("P2", "Analysis Designer", f"Designing analysis for: {node.statement[:50]}...")
            node.analysis = self.analysis_designer.design(node=node, testability=node.testability, industry=industry, company=company, question=question)
            _emit("P2", "Analysis Designer", f"=> {node.analysis.analysis_type.value} ({node.analysis.loe_hours}h)")

    def generate_tree(self, industry: str, company: str, question: str, project_id: str = "") -> HypothesisTree:
        if project_id:
            set_current_project(project_id)

        _emit("P1", "Orchestrator", "Starting hypothesis tree generation")
        classification = self.classify_question(industry, company, question)
        _emit("P1", "Orchestrator", f"Classification: {classification.question_type.value} ({classification.confidence:.0%})")

        root = self.generate_root_and_branches(industry, company, question, classification)
        self._decompose_recursive(root, industry, company, question, TARGET_TREE_DEPTH)
        all_nodes = self._collect_all(root)
        leaves = [n for n in all_nodes if n.is_leaf]
        _emit("P1", "Orchestrator", f"Phase 1 complete: {len(all_nodes)} nodes, {len(leaves)} leaves")

        _emit("P2", "Orchestrator", f"Starting testability classification for {len(leaves)} leaves")
        self._classify_and_design(root, industry, company, question)
        _emit("P2", "Orchestrator", "Phase 2 complete")

        _emit("P3", "Data Retrieval", "Fetching financial data from public sources...")
        self.data_retrieval.retrieve_for_tree(root, industry, company, question)
        data_count = len([n for n in all_nodes if n.data_card and n.data_card.data_points])
        _emit("P3", "Data Retrieval", f"Phase 3 complete: {data_count} leaves with data")

        tree = HypothesisTree(root=root, classification=classification, industry=industry, company=company, question=question)

        _emit("P4", "Red Team", "Starting adversarial stress-testing...")
        tree.stress_test_report = self.red_team.stress_test(tree)
        _emit("P4", "Red Team", f"Phase 4 complete: {tree.stress_test_report.critical_count} critical, {tree.stress_test_report.warning_count} warnings")

        _emit("P5", "DAG Builder", "Constructing causal dependency graph...")
        tree.causal_dag = self.dag_builder.build_dag(root)
        _emit("P5", "DAG Builder", f"Phase 5 complete: {len(tree.causal_dag.edges)} edges")

        _emit("P6", "Workplan", "Compiling workplan from analysis plan...")
        workplan = self.workplan_agent.compile_workplan(root, industry, company, question)
        tree.workplan = workplan.model_dump()
        _emit("P6", "Workplan", f"Phase 6 complete: {len(workplan.workstreams)} workstreams, {workplan.total_loe:.0f}h")

        _emit("done", "Orchestrator", "All phases complete. Tree ready.")
        return tree

    @staticmethod
    def _collect_all(node):
        result = [node]
        for child in node.children: result.extend(OrchestratorAgent._collect_all(child))
        return result
PYEOF

# ======================== SSE ENDPOINT + UPDATED PROJECTS ROUTER ========================
cat > apps/api/app/routers/projects.py << 'PYEOF'
"""Project endpoints with SSE log streaming."""
from __future__ import annotations

import asyncio
import json
import logging
import uuid
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

from packages.agents.orchestrator.agent import OrchestratorAgent
from packages.shared.types import ProjectCreate, ProjectResponse
from app.services.orchestrator import get_or_create_queue, get_logs, clear_logs

logger = logging.getLogger(__name__)
router = APIRouter(tags=["projects"])

_projects: dict[str, dict] = {}
_executor = ThreadPoolExecutor(max_workers=2)


@router.post("/projects", response_model=ProjectResponse)
async def create_project(body: ProjectCreate):
    project_id = str(uuid.uuid4())
    project = {"id": project_id, "industry": body.industry, "company": body.company,
        "question": body.question, "status": "created", "tree": None, "created_at": datetime.utcnow()}
    _projects[project_id] = project
    return ProjectResponse(**project)


def _run_generation(project_id: str, industry: str, company: str, question: str):
    """Run in thread pool to not block the event loop."""
    try:
        tree = OrchestratorAgent().generate_tree(industry, company, question, project_id=project_id)
        _projects[project_id]["tree"] = tree
        _projects[project_id]["status"] = "complete"
    except Exception as e:
        logger.exception("Generation failed")
        _projects[project_id]["status"] = "error"
        _projects[project_id]["error"] = str(e)


@router.post("/projects/{project_id}/generate", response_model=ProjectResponse)
async def generate_tree(project_id: str):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404, "Project not found")
    if project["tree"]: raise HTTPException(400, "Already generated")
    project["status"] = "generating"

    # Run in background thread
    loop = asyncio.get_event_loop()
    loop.run_in_executor(_executor, _run_generation, project_id, project["industry"], project["company"], project["question"])

    # Return immediately so frontend can start polling SSE
    return ProjectResponse(**project)


@router.get("/projects/{project_id}/stream")
async def stream_logs(project_id: str):
    """SSE endpoint streaming real-time agent logs."""
    queue = get_or_create_queue(project_id)

    async def event_generator():
        # First send any logs already accumulated
        for entry in get_logs(project_id):
            yield f"data: {json.dumps(entry)}\n\n"

        # Then stream new ones
        while True:
            try:
                entry = await asyncio.wait_for(queue.get(), timeout=1.0)
                yield f"data: {json.dumps(entry)}\n\n"
                if entry.get("phase") == "done":
                    break
            except asyncio.TimeoutError:
                yield f": keepalive\n\n"
                # Check if project is done
                project = _projects.get(project_id)
                if project and project["status"] in ("complete", "error"):
                    yield f"data: {json.dumps({'phase': 'done', 'agent': 'System', 'message': project['status'], 'level': 'info'})}\n\n"
                    break

    return StreamingResponse(event_generator(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive", "X-Accel-Buffering": "no"})


@router.get("/projects/{project_id}", response_model=ProjectResponse)
async def get_project(project_id: str):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    return ProjectResponse(**project)


@router.get("/projects", response_model=list[ProjectResponse])
async def list_projects():
    return [ProjectResponse(**p) for p in _projects.values()]
PYEOF

# ======================== FILE UPLOAD ENDPOINT ========================
cat > apps/api/app/routers/health.py << 'PYEOF'
import os
import uuid
import logging
from fastapi import APIRouter, UploadFile, File
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)
router = APIRouter(tags=["health"])

UPLOAD_DIR = "/tmp/hypotree_uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)


@router.get("/health")
async def health():
    return {"status": "ok", "version": "0.7.0"}


@router.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    """Accept PDF, CSV, Excel, or image uploads."""
    file_id = str(uuid.uuid4())[:8]
    ext = os.path.splitext(file.filename or "")[1].lower()
    allowed = {".pdf", ".csv", ".xlsx", ".xls", ".png", ".jpg", ".jpeg"}

    if ext not in allowed:
        return JSONResponse(status_code=400, content={"detail": f"Unsupported file type: {ext}"})

    path = os.path.join(UPLOAD_DIR, f"{file_id}{ext}")
    content = await file.read()
    with open(path, "wb") as f:
        f.write(content)

    file_info = {
        "id": file_id,
        "filename": file.filename,
        "extension": ext,
        "size_bytes": len(content),
        "path": path,
    }

    # Parse based on type
    parsed = _parse_file(path, ext)
    file_info["parsed"] = parsed

    logger.info("Uploaded %s (%d bytes) -> %s", file.filename, len(content), path)
    return file_info


def _parse_file(path: str, ext: str) -> dict:
    """Extract structured content from uploaded file."""
    if ext == ".pdf":
        return _parse_pdf(path)
    elif ext == ".csv":
        return _parse_csv(path)
    elif ext in (".xlsx", ".xls"):
        return _parse_excel(path)
    elif ext in (".png", ".jpg", ".jpeg"):
        return {"type": "image", "note": "Image uploaded. Vision analysis available in future phase."}
    return {}


def _parse_pdf(path: str) -> dict:
    try:
        import pymupdf
        doc = pymupdf.open(path)
        pages = []
        for i, page in enumerate(doc):
            text = page.get_text()
            pages.append({"page": i + 1, "text": text[:2000], "chars": len(text)})
        return {"type": "pdf", "pages": len(doc), "content": pages[:10]}
    except Exception as e:
        return {"type": "pdf", "error": str(e)}


def _parse_csv(path: str) -> dict:
    try:
        import csv
        with open(path, "r") as f:
            reader = csv.reader(f)
            headers = next(reader, [])
            rows = []
            for i, row in enumerate(reader):
                if i >= 5: break
                rows.append(row)
        return {"type": "csv", "headers": headers, "sample_rows": rows, "column_count": len(headers)}
    except Exception as e:
        return {"type": "csv", "error": str(e)}


def _parse_excel(path: str) -> dict:
    try:
        import openpyxl
        wb = openpyxl.load_workbook(path, read_only=True)
        sheets = []
        for name in wb.sheetnames[:3]:
            ws = wb[name]
            rows = []
            for i, row in enumerate(ws.iter_rows(values_only=True)):
                if i >= 6: break
                rows.append([str(c) if c is not None else "" for c in row])
            sheets.append({"name": name, "rows": rows})
        return {"type": "excel", "sheets": sheets}
    except Exception as e:
        return {"type": "excel", "error": str(e)}
PYEOF

# ======================== BENCHMARK AGENT ========================
cat > packages/agents/benchmark/prompts.py << 'PYEOF'
BENCHMARK_PROMPT = """You are a strategy consulting analyst finding comparable cases.

Context:
- Industry: {industry}
- Company: {company}
- Question: {question}

For the following hypothesis that contains a quantitative assumption, find analogous historical cases.

Hypothesis: "{statement}"
Assumption to benchmark: "{assumption}"

Available financial data:
{available_data}

Find 3-5 comparable situations (mergers, market entries, cost programs, etc.) from the same or adjacent industries. For each, provide:
- The company/entities involved
- What happened (brief)
- The relevant metric/outcome
- How it compares to the assumption being tested

Respond ONLY with valid JSON, no markdown fences:
{{
  "comparables": [
    {{
      "entities": "<companies involved>",
      "description": "<what happened, 1-2 sentences>",
      "metric": "<the relevant metric>",
      "value": "<actual outcome value>",
      "source": "<where this data comes from>",
      "relevance": "<how this compares to the assumption>"
    }}
  ],
  "distribution_summary": "<1-2 sentences: median, range, where the assumption falls>"
}}"""
PYEOF

cat > packages/agents/benchmark/agent.py << 'PYEOF'
"""Benchmark Agent — finds comparable cases for assumptions."""
from __future__ import annotations

import json
import logging
from typing import Optional

from packages.agents.base import BaseAgent, _emit
from packages.agents.benchmark.prompts import BENCHMARK_PROMPT
from packages.shared.types import HypothesisNode

logger = logging.getLogger(__name__)


class BenchmarkAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a strategy consulting analyst specializing in comparable case analysis."

    def find_comparables(
        self, node: HypothesisNode, industry: str, company: str, question: str,
        available_data: str = "",
    ) -> Optional[dict]:
        assumption = node.what_must_be_true or node.statement

        _emit("P7", "Benchmark Agent", f"Finding comparables for: {node.statement[:50]}...")

        prompt = BENCHMARK_PROMPT.format(
            industry=industry, company=company, question=question,
            statement=node.statement, assumption=assumption,
            available_data=available_data or "No additional data available.",
        )

        try:
            raw = self.call_llm(prompt)
            data = json.loads(raw)
            _emit("P7", "Benchmark Agent",
                f"Found {len(data.get('comparables', []))} comparables")
            return data
        except Exception as e:
            logger.warning("Benchmark failed for '%s': %s", node.statement[:50], e)
            return None
PYEOF

# ======================== FRONTEND: LIVE TERMINAL FEED ========================
cat > apps/web/src/components/common/LiveAgentStatus.tsx << 'TSEOF'
import { useState, useEffect, useRef } from 'react';

interface LogEntry {
  ts: number;
  phase: string;
  agent: string;
  message: string;
  level: string;
}

const PHASE_COLORS: Record<string, string> = {
  P1: '#6366f1', P2: '#3b82f6', P3: '#22c55e',
  P4: '#ef4444', P5: '#a855f7', P6: '#f59e0b',
  P7: '#14b8a6', done: '#22c55e',
};

const PHASE_LABELS: Record<string, string> = {
  P1: 'Hypothesis Decomposition', P2: 'Testability & Analysis',
  P3: 'Data Pre-Population', P4: 'Adversarial Stress-Test',
  P5: 'Causal DAG', P6: 'Workplan Synthesis', P7: 'Benchmarking',
  done: 'Complete',
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
  const bottomRef = useRef<HTMLDivElement>(null);

  // Timer
  useEffect(() => {
    const t = setInterval(() => setElapsed(Math.floor((Date.now() - startTime) / 1000)), 1000);
    return () => clearInterval(t);
  }, [startTime]);

  // SSE connection
  useEffect(() => {
    if (!projectId) return;

    const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    const es = new EventSource(`${apiUrl}/api/projects/${projectId}/stream`);

    es.onmessage = (event) => {
      try {
        const entry: LogEntry = JSON.parse(event.data);
        setLogs((prev) => [...prev, entry]);
        if (entry.phase && entry.phase !== 'done') setCurrentPhase(entry.phase);
        if (entry.phase === 'done') {
          es.close();
          // Poll for completed project
          setTimeout(onComplete, 1500);
        }
      } catch (e) {
        // ignore parse errors on keepalive
      }
    };

    es.onerror = () => {
      // SSE reconnects automatically, but check if done
      setTimeout(onComplete, 3000);
    };

    return () => es.close();
  }, [projectId, onComplete]);

  // Auto-scroll
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [logs]);

  const formatTime = (s: number) => `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, '0')}`;

  const phases = [...new Set(logs.map((l) => l.phase).filter((p) => p && p !== 'done' && p !== ''))];

  return (
    <div className="max-w-4xl mx-auto py-8">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <div className="w-3 h-3 rounded-full animate-pulse" style={{ background: PHASE_COLORS[currentPhase] || '#6366f1' }} />
          <div>
            <h2 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>
              {PHASE_LABELS[currentPhase] || currentPhase}
            </h2>
            <p className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>
              {logs.length} events &middot; {formatTime(elapsed)}
            </p>
          </div>
        </div>
      </div>

      {/* Phase progress pills */}
      <div className="flex gap-1.5 mb-4">
        {['P1', 'P2', 'P3', 'P4', 'P5', 'P6'].map((p) => {
          const done = phases.indexOf(p) < phases.indexOf(currentPhase);
          const active = p === currentPhase;
          return (
            <div key={p} className="flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-mono"
              style={{
                background: active ? PHASE_COLORS[p] + '22' : done ? 'var(--bg-card)' : 'var(--bg-secondary)',
                border: `1px solid ${active ? PHASE_COLORS[p] : 'var(--border-subtle)'}`,
                color: active ? PHASE_COLORS[p] : done ? 'var(--accent-green)' : 'var(--text-muted)',
              }}>
              {done ? '\u2713' : active ? '\u25CF' : '\u25CB'} {p}
            </div>
          );
        })}
      </div>

      {/* Terminal log feed */}
      <div className="rounded-xl overflow-hidden" style={{ background: '#0a0c10', border: '1px solid var(--border-subtle)' }}>
        {/* Terminal title bar */}
        <div className="flex items-center gap-2 px-4 py-2" style={{ background: '#12141c', borderBottom: '1px solid var(--border-subtle)' }}>
          <div className="flex gap-1.5">
            <span className="w-3 h-3 rounded-full" style={{ background: '#ef4444' }} />
            <span className="w-3 h-3 rounded-full" style={{ background: '#f59e0b' }} />
            <span className="w-3 h-3 rounded-full" style={{ background: '#22c55e' }} />
          </div>
          <span className="text-xs font-mono ml-2" style={{ color: 'var(--text-muted)' }}>hypotree agent pipeline</span>
        </div>

        {/* Log entries */}
        <div className="p-4 overflow-y-auto font-mono text-xs leading-relaxed" style={{ maxHeight: '55vh', minHeight: '300px' }}>
          {logs.map((entry, i) => {
            const phaseColor = PHASE_COLORS[entry.phase] || '#6b7280';
            const isWarning = entry.level === 'warning';
            return (
              <div key={i} className="flex gap-2 py-0.5 hover:bg-white hover:bg-opacity-[0.02] transition-colors">
                <span style={{ color: 'var(--text-muted)', minWidth: '52px' }}>
                  {new Date(entry.ts * 1000).toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                </span>
                <span className="font-semibold" style={{ color: phaseColor, minWidth: '24px' }}>
                  {entry.phase || '--'}
                </span>
                <span style={{ color: '#e2e8f0', minWidth: '160px' }}>
                  {entry.agent}
                </span>
                <span style={{ color: isWarning ? '#fbbf24' : 'var(--text-secondary)' }}>
                  {entry.message}
                </span>
              </div>
            );
          })}

          {/* Blinking cursor */}
          <div className="flex items-center gap-1 mt-1">
            <span className="inline-block w-2 h-4 animate-pulse" style={{ background: PHASE_COLORS[currentPhase] || '#6366f1' }} />
          </div>
          <div ref={bottomRef} />
        </div>
      </div>
    </div>
  );
}
TSEOF

# ======================== FRONTEND: Updated App.tsx — SSE integration ========================
cat > apps/web/src/App.tsx << 'TSEOF'
import { useState, useCallback } from 'react';
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
      // generate_tree now returns immediately (runs in background)
      await api.generateTree(created.id);
      // SSE stream handles the rest via LiveAgentStatus
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unknown error');
      setLoading(false);
    }
  };

  const handleStreamComplete = useCallback(async () => {
    if (!projectId) return;
    try {
      const result = await api.getProject(projectId);
      if (result.tree) {
        setProject(result);
      } else {
        // Poll a few more times
        for (let i = 0; i < 10; i++) {
          await new Promise((r) => setTimeout(r, 2000));
          const retry = await api.getProject(projectId);
          if (retry.tree) { setProject(retry); break; }
          if (retry.status === 'error') { setError('Generation failed'); break; }
        }
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to fetch results');
    } finally {
      setLoading(false);
    }
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
              <div className="flex items-center gap-1 p-1 rounded-xl" style={{ background: 'var(--bg-primary)' }}>
                {visibleTabs.map((tab) => (
                  <button key={tab.key} onClick={() => setViewMode(tab.key)}
                    className="px-4 py-1.5 text-sm rounded-lg transition-all duration-200"
                    style={{ background: viewMode === tab.key ? 'var(--accent-indigo)' : 'transparent', color: viewMode === tab.key ? 'white' : 'var(--text-secondary)', fontWeight: viewMode === tab.key ? 600 : 400 }}>
                    <span className="mr-1.5">{tab.icon}</span>{tab.label}
                    {tab.key === 'stress' && project?.tree?.stress_test_report && (
                      <span className="ml-1.5 text-xs px-1.5 py-0.5 rounded-full" style={{ background: 'var(--accent-red)', color: 'white' }}>{project.tree.stress_test_report.critical_count}</span>
                    )}
                  </button>
                ))}
              </div>
            )}
            {(project || loading) && <button onClick={handleReset} className="text-sm px-3 py-1.5 rounded-lg" style={{ color: 'var(--accent-indigo)', border: '1px solid var(--border-subtle)' }}>New Analysis</button>}
          </div>
        </header>

        <main className="max-w-screen-2xl mx-auto py-6 px-6">
          {error && <div className="mb-6 p-4 rounded-xl border text-sm" style={{ background: '#1c1012', borderColor: 'var(--accent-red)', color: '#fca5a5' }}>{error}</div>}
          {loading && <LiveAgentStatus projectId={projectId} onComplete={handleStreamComplete} />}
          {!loading && !project && <QuestionInput onSubmit={handleSubmit} loading={loading} />}
          {!loading && project?.tree && (
            <div>
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

# ======================== API CLIENT — updated for SSE flow ========================
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
  uploadFile: async (file: File) => {
    const form = new FormData();
    form.append('file', file);
    const res = await fetch(`${API_URL}/api/upload`, { method: 'POST', body: form });
    if (!res.ok) throw new Error('Upload failed');
    return res.json();
  },
};
TSEOF

echo ""
echo "=== Phase 7 files written ==="
echo ""
echo "What changed:"
echo ""
echo "BACKEND:"
echo "  - SSE log streaming: /api/projects/{id}/stream sends real-time agent logs"
echo "  - Generation now runs in background thread, returns immediately"
echo "  - Every agent emits structured logs (phase, agent, message) via _emit()"
echo "  - File upload endpoint: POST /api/upload (PDF, CSV, Excel, images)"
echo "  - PDF parsing via PyMuPDF, CSV parsing, Excel parsing via openpyxl"
echo "  - Benchmark Agent: finds comparable cases for quantitative assumptions"
echo ""
echo "FRONTEND:"
echo "  - LIVE TERMINAL: real terminal-style feed showing every agent log as it happens"
echo "    - macOS-style title bar with traffic lights"
echo "    - Color-coded by phase, timestamped, auto-scrolling"
echo "    - Phase progress pills at top"
echo "    - Blinking cursor at current position"
echo "  - SSE connection streams logs in real time (no polling)"
echo "  - Automatically fetches completed project when 'done' event arrives"
echo ""
echo "Run: restart uvicorn + npm run dev, generate a new tree."
echo "Watch the live terminal feed during generation."