#!/bin/bash
set -e

# ============================================================
# HypoTree Phase 1 — Core Hypothesis Engine
# Run from hypotree/ root
# Usage: bash phase1.sh
# ============================================================

echo "=== Phase 1: Core Hypothesis Engine ==="

# ======================== SHARED TYPES ========================
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


class HypothesisNode(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4())[:8])
    statement: str
    parent_id: Optional[str] = None
    children: list[HypothesisNode] = Field(default_factory=list)
    depth: int = 0
    what_must_be_true: Optional[str] = None
    evidence_needed: Optional[str] = None
    is_leaf: bool = False

    class Config:
        arbitrary_types_allowed = True


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

# ======================== SHARED CONSTANTS ========================
cat > packages/shared/constants.py << 'PYEOF'
MAX_TREE_DEPTH = 4
TARGET_TREE_DEPTH = 3
MECE_MAX_RETRIES = 3
LLM_MAX_RETRIES = 3
DEFAULT_MODEL = "claude-sonnet-4-20250514"
ORCHESTRATOR_MODEL = "claude-sonnet-4-20250514"
PYEOF

# ======================== AGENT BASE CLASS ========================
cat > packages/agents/base.py << 'PYEOF'
"""Base class for all HypoTree agents."""
from __future__ import annotations

import logging
import time
from abc import ABC, abstractmethod
from typing import Any, TypeVar

import anthropic

from packages.shared.constants import DEFAULT_MODEL, LLM_MAX_RETRIES

logger = logging.getLogger(__name__)

T = TypeVar("T")


class BaseAgent(ABC):
    """Every agent follows the same structural pattern (spec §8.2)."""

    def __init__(self, model: str = DEFAULT_MODEL):
        self.model = model
        self.client = anthropic.Anthropic()

    @abstractmethod
    def get_system_prompt(self) -> str:
        ...

    def call_llm(self, user_prompt: str, system_prompt: str | None = None) -> str:
        sys = system_prompt or self.get_system_prompt()
        last_error: Exception | None = None

        for attempt in range(LLM_MAX_RETRIES):
            try:
                start = time.time()
                response = self.client.messages.create(
                    model=self.model,
                    max_tokens=4096,
                    system=sys,
                    messages=[{"role": "user", "content": user_prompt}],
                )
                elapsed = time.time() - start
                text = response.content[0].text
                logger.info(
                    "Agent=%s model=%s tokens_in=%d tokens_out=%d latency=%.2fs attempt=%d",
                    self.__class__.__name__,
                    self.model,
                    response.usage.input_tokens,
                    response.usage.output_tokens,
                    elapsed,
                    attempt + 1,
                )
                return text
            except Exception as e:
                last_error = e
                logger.warning(
                    "Agent=%s attempt=%d error=%s", self.__class__.__name__, attempt + 1, str(e)
                )

        raise RuntimeError(
            f"Agent {self.__class__.__name__} failed after {LLM_MAX_RETRIES} attempts: {last_error}"
        )
PYEOF

# ======================== ORCHESTRATOR SCHEMAS ========================
cat > packages/agents/orchestrator/schemas.py << 'PYEOF'
from packages.shared.types import ClassificationResult, HypothesisTree, ProjectCreate
PYEOF

# ======================== ORCHESTRATOR PROMPTS ========================
cat > packages/agents/orchestrator/prompts.py << 'PYEOF'
CLASSIFICATION_PROMPT = """You are a strategy consulting expert. Given a strategic question, classify it into exactly one category and select the appropriate decomposition framework.

Categories:
- growth_market_entry: Questions about entering new markets, expanding geographically, launching new products
- cost_optimization: Questions about reducing costs, improving efficiency, streamlining operations
- ma_rationale: Questions about mergers, acquisitions, divestitures, joint ventures
- pricing_strategy: Questions about pricing models, price changes, value capture
- competitive_response: Questions about responding to competitor actions, competitive positioning
- digital_transformation: Questions about technology investment, AI adoption, digital capabilities

Respond ONLY with valid JSON, no markdown fences:
{{
  "question_type": "<category>",
  "framework": "<framework>",
  "confidence": <0.0-1.0>,
  "rationale": "<one sentence>"
}}

Framework mapping:
- growth_market_entry -> 3cs_market_attractiveness
- cost_optimization -> value_chain_decomposition
- ma_rationale -> synergy_tree_standalone
- pricing_strategy -> value_based_pricing
- competitive_response -> game_theory_porters
- digital_transformation -> capability_maturity_roi

Strategic question:
Industry: {industry}
Company: {company}
Question: {question}"""

ROOT_HYPOTHESIS_PROMPT = """You are a strategy consulting expert building a hypothesis tree.

Context:
- Industry: {industry}
- Company: {company}
- Question: {question}
- Question Type: {question_type}
- Framework: {framework}

Generate the ROOT hypothesis and its FIRST-LEVEL children (3-5 branches). These first-level branches must be MECE (Mutually Exclusive, Collectively Exhaustive) — they should not overlap and together should cover the full scope of the question.

For each node provide:
- statement: the hypothesis
- what_must_be_true: what conditions validate this hypothesis
- evidence_needed: what data or analysis would prove/disprove it

Respond ONLY with valid JSON, no markdown fences:
{{
  "root": {{
    "statement": "<root hypothesis>",
    "what_must_be_true": "<condition>",
    "evidence_needed": "<evidence>"
  }},
  "children": [
    {{
      "statement": "<branch hypothesis>",
      "what_must_be_true": "<condition>",
      "evidence_needed": "<evidence>"
    }}
  ]
}}"""
PYEOF

# ======================== ORCHESTRATOR AGENT ========================
cat > packages/agents/orchestrator/agent.py << 'PYEOF'
"""Orchestrator agent — routes tasks, classifies questions, manages tree generation."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.decomposer.agent import DecomposerAgent
from packages.agents.mece_validator.agent import MECEValidatorAgent
from packages.agents.orchestrator.prompts import CLASSIFICATION_PROMPT, ROOT_HYPOTHESIS_PROMPT
from packages.shared.constants import MECE_MAX_RETRIES, ORCHESTRATOR_MODEL, TARGET_TREE_DEPTH
from packages.shared.types import (
    ClassificationResult,
    Framework,
    HypothesisNode,
    HypothesisTree,
    QuestionType,
)

logger = logging.getLogger(__name__)


class OrchestratorAgent(BaseAgent):
    def __init__(self) -> None:
        super().__init__(model=ORCHESTRATOR_MODEL)
        self.decomposer = DecomposerAgent()
        self.mece_validator = MECEValidatorAgent()

    def get_system_prompt(self) -> str:
        return "You are a strategy consulting orchestrator."

    def classify_question(self, industry: str, company: str, question: str) -> ClassificationResult:
        prompt = CLASSIFICATION_PROMPT.format(industry=industry, company=company, question=question)
        raw = self.call_llm(prompt)
        data = json.loads(raw)
        return ClassificationResult(
            question_type=QuestionType(data["question_type"]),
            framework=Framework(data["framework"]),
            confidence=data["confidence"],
            rationale=data["rationale"],
        )

    def generate_root_and_branches(
        self, industry: str, company: str, question: str, classification: ClassificationResult
    ) -> HypothesisNode:
        prompt = ROOT_HYPOTHESIS_PROMPT.format(
            industry=industry,
            company=company,
            question=question,
            question_type=classification.question_type.value,
            framework=classification.framework.value,
        )
        raw = self.call_llm(prompt)
        data = json.loads(raw)

        root = HypothesisNode(
            statement=data["root"]["statement"],
            what_must_be_true=data["root"].get("what_must_be_true"),
            evidence_needed=data["root"].get("evidence_needed"),
            depth=0,
        )

        for child_data in data["children"]:
            child = HypothesisNode(
                statement=child_data["statement"],
                parent_id=root.id,
                what_must_be_true=child_data.get("what_must_be_true"),
                evidence_needed=child_data.get("evidence_needed"),
                depth=1,
            )
            root.children.append(child)

        return root

    def _decompose_recursive(
        self,
        node: HypothesisNode,
        industry: str,
        company: str,
        question: str,
        target_depth: int,
    ) -> None:
        if node.depth >= target_depth:
            node.is_leaf = True
            return

        if not node.children:
            children = self.decomposer.decompose(
                parent=node,
                industry=industry,
                company=company,
                question=question,
            )

            # MECE validation with retry
            for attempt in range(MECE_MAX_RETRIES):
                validation = self.mece_validator.validate(
                    parent=node, children=children
                )
                if validation.is_valid:
                    break
                logger.info(
                    "MECE validation failed attempt=%d overlaps=%s gaps=%s",
                    attempt + 1,
                    validation.overlaps,
                    validation.gaps,
                )
                children = self.decomposer.decompose(
                    parent=node,
                    industry=industry,
                    company=company,
                    question=question,
                    previous_issues=validation,
                )

            for child in children:
                child.parent_id = node.id
                child.depth = node.depth + 1
                node.children.append(child)

        for child in node.children:
            self._decompose_recursive(child, industry, company, question, target_depth)

    def generate_tree(self, industry: str, company: str, question: str) -> HypothesisTree:
        logger.info("Starting tree generation: %s / %s / %s", industry, company, question)

        classification = self.classify_question(industry, company, question)
        logger.info("Classification: %s (%.2f)", classification.question_type, classification.confidence)

        root = self.generate_root_and_branches(industry, company, question, classification)
        logger.info("Root generated with %d first-level branches", len(root.children))

        self._decompose_recursive(root, industry, company, question, TARGET_TREE_DEPTH)

        leaf_count = len([n for n in self._collect_all(root) if n.is_leaf])
        logger.info("Tree complete: %d total nodes, %d leaves", len(self._collect_all(root)), leaf_count)

        return HypothesisTree(
            root=root,
            classification=classification,
            industry=industry,
            company=company,
            question=question,
        )

    @staticmethod
    def _collect_all(node: HypothesisNode) -> list[HypothesisNode]:
        result = [node]
        for child in node.children:
            result.extend(OrchestratorAgent._collect_all(child))
        return result
PYEOF

# ======================== DECOMPOSER PROMPTS ========================
cat > packages/agents/decomposer/prompts.py << 'PYEOF'
DECOMPOSE_PROMPT = """You are a strategy consulting expert. Decompose the given hypothesis into 2-4 sub-hypotheses that are MECE (Mutually Exclusive, Collectively Exhaustive).

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

Parent hypothesis: "{parent_statement}"
Current depth: {depth} (target max depth: {target_depth})

{issues_section}

Generate 2-4 sub-hypotheses. Each must be:
- Mutually exclusive: no overlap in scope with siblings
- Collectively exhaustive: together they fully cover the parent hypothesis
- Specific and testable: not vague or generic
- At the right level of detail for depth {next_depth}

Respond ONLY with valid JSON, no markdown fences:
{{
  "children": [
    {{
      "statement": "<sub-hypothesis>",
      "what_must_be_true": "<what condition validates this>",
      "evidence_needed": "<what data proves/disproves this>"
    }}
  ]
}}"""

ISSUES_TEMPLATE = """Previous decomposition had issues:
- Overlaps: {overlaps}
- Gaps: {gaps}
- Suggestions: {suggestions}

Fix these issues in the new decomposition."""
PYEOF

# ======================== DECOMPOSER AGENT ========================
cat > packages/agents/decomposer/agent.py << 'PYEOF'
"""Decomposer agent — generates sub-hypotheses for a parent node."""
from __future__ import annotations

import json
import logging
from typing import Optional

from packages.agents.base import BaseAgent
from packages.agents.decomposer.prompts import DECOMPOSE_PROMPT, ISSUES_TEMPLATE
from packages.shared.constants import TARGET_TREE_DEPTH
from packages.shared.types import HypothesisNode, MECEValidationResult

logger = logging.getLogger(__name__)


class DecomposerAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a strategy consulting expert specializing in hypothesis decomposition."

    def decompose(
        self,
        parent: HypothesisNode,
        industry: str,
        company: str,
        question: str,
        previous_issues: Optional[MECEValidationResult] = None,
    ) -> list[HypothesisNode]:
        issues_section = ""
        if previous_issues and not previous_issues.is_valid:
            issues_section = ISSUES_TEMPLATE.format(
                overlaps=", ".join(previous_issues.overlaps) or "none",
                gaps=", ".join(previous_issues.gaps) or "none",
                suggestions=", ".join(previous_issues.suggestions) or "none",
            )

        prompt = DECOMPOSE_PROMPT.format(
            industry=industry,
            company=company,
            question=question,
            parent_statement=parent.statement,
            depth=parent.depth,
            target_depth=TARGET_TREE_DEPTH,
            next_depth=parent.depth + 1,
            issues_section=issues_section,
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        children: list[HypothesisNode] = []
        for child_data in data["children"]:
            child = HypothesisNode(
                statement=child_data["statement"],
                what_must_be_true=child_data.get("what_must_be_true"),
                evidence_needed=child_data.get("evidence_needed"),
            )
            children.append(child)

        logger.info(
            "Decomposed '%s' into %d children", parent.statement[:50], len(children)
        )
        return children
PYEOF

# ======================== MECE VALIDATOR PROMPTS ========================
cat > packages/agents/mece_validator/prompts.py << 'PYEOF'
MECE_VALIDATION_PROMPT = """You are an adversarial MECE validator for strategy consulting hypothesis trees.

Your job is to rigorously check whether a set of sibling hypotheses satisfies MECE:
- Mutually Exclusive: No two siblings should overlap in scope. If testing one could partially answer another, they overlap.
- Collectively Exhaustive: Together, the siblings must fully cover the parent hypothesis. If there's an important aspect of the parent not addressed by any child, there's a gap.

Parent hypothesis: "{parent_statement}"

Sibling hypotheses:
{siblings_list}

Evaluate rigorously. Be critical — err on the side of finding issues.

Respond ONLY with valid JSON, no markdown fences:
{{
  "is_valid": true/false,
  "overlaps": ["<description of overlap between sibling X and Y>"],
  "gaps": ["<aspect of parent not covered by any sibling>"],
  "suggestions": ["<how to fix each issue>"]
}}"""
PYEOF

# ======================== MECE VALIDATOR AGENT ========================
cat > packages/agents/mece_validator/agent.py << 'PYEOF'
"""MECE Validator agent — adversarial check for mutual exclusivity and collective exhaustiveness."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.mece_validator.prompts import MECE_VALIDATION_PROMPT
from packages.shared.types import HypothesisNode, MECEValidationResult

logger = logging.getLogger(__name__)


class MECEValidatorAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a rigorous MECE validator. Be adversarial and critical."

    def validate(
        self, parent: HypothesisNode, children: list[HypothesisNode]
    ) -> MECEValidationResult:
        siblings_list = "\n".join(
            f"  {i + 1}. {child.statement}" for i, child in enumerate(children)
        )

        prompt = MECE_VALIDATION_PROMPT.format(
            parent_statement=parent.statement,
            siblings_list=siblings_list,
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        result = MECEValidationResult(
            is_valid=data["is_valid"],
            overlaps=data.get("overlaps", []),
            gaps=data.get("gaps", []),
            suggestions=data.get("suggestions", []),
        )

        logger.info(
            "MECE validation for '%s': valid=%s overlaps=%d gaps=%d",
            parent.statement[:50],
            result.is_valid,
            len(result.overlaps),
            len(result.gaps),
        )
        return result
PYEOF

# ======================== BACKEND CONFIG ========================
cat > apps/api/app/config.py << 'PYEOF'
import os
import sys

from pydantic_settings import BaseSettings

# Add project root to path so packages are importable
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)


class Settings(BaseSettings):
    anthropic_api_key: str = ""
    openai_api_key: str = ""
    database_url: str = "postgresql+asyncpg://hypotree:hypotree@localhost:5432/hypotree"
    redis_url: str = "redis://localhost:6379/0"
    serp_api_key: str = ""
    alpha_vantage_api_key: str = ""
    langsmith_api_key: str = ""
    langsmith_project: str = "hypotree"
    environment: str = "development"
    log_level: str = "INFO"
    cors_origins: str = "http://localhost:5173"

    class Config:
        env_file = ".env"


settings = Settings()
PYEOF

# ======================== BACKEND MAIN ========================
cat > apps/api/app/main.py << 'PYEOF'
import logging
import os
import sys

# Ensure project root is in path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.routers import health, projects

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
PYEOF

# ======================== HEALTH ROUTER ========================
cat > apps/api/app/routers/health.py << 'PYEOF'
from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
async def health():
    return {"status": "ok", "version": "0.1.0"}
PYEOF

# ======================== PROJECTS ROUTER ========================
cat > apps/api/app/routers/projects.py << 'PYEOF'
"""Project endpoints — create projects and generate hypothesis trees."""
from __future__ import annotations

import logging
import uuid
from datetime import datetime

from fastapi import APIRouter, HTTPException

from packages.agents.orchestrator.agent import OrchestratorAgent
from packages.shared.types import HypothesisTree, ProjectCreate, ProjectResponse

logger = logging.getLogger(__name__)

router = APIRouter(tags=["projects"])

# In-memory store (replaced with PostgreSQL in Phase 8+)
_projects: dict[str, dict] = {}


@router.post("/projects", response_model=ProjectResponse)
async def create_project(body: ProjectCreate):
    project_id = str(uuid.uuid4())
    project = {
        "id": project_id,
        "industry": body.industry,
        "company": body.company,
        "question": body.question,
        "status": "created",
        "tree": None,
        "created_at": datetime.utcnow(),
    }
    _projects[project_id] = project
    return ProjectResponse(**project)


@router.post("/projects/{project_id}/generate", response_model=ProjectResponse)
async def generate_tree(project_id: str):
    project = _projects.get(project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    if project["tree"] is not None:
        raise HTTPException(status_code=400, detail="Tree already generated")

    project["status"] = "generating"

    try:
        orchestrator = OrchestratorAgent()
        tree = orchestrator.generate_tree(
            industry=project["industry"],
            company=project["company"],
            question=project["question"],
        )
        project["tree"] = tree
        project["status"] = "complete"
    except Exception as e:
        logger.exception("Tree generation failed")
        project["status"] = "error"
        raise HTTPException(status_code=500, detail=str(e))

    return ProjectResponse(**project)


@router.get("/projects/{project_id}", response_model=ProjectResponse)
async def get_project(project_id: str):
    project = _projects.get(project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")
    return ProjectResponse(**project)


@router.get("/projects", response_model=list[ProjectResponse])
async def list_projects():
    return [ProjectResponse(**p) for p in _projects.values()]
PYEOF

# ======================== ROUTERS __init__ ========================
cat > apps/api/app/routers/__init__.py << 'PYEOF'
PYEOF

# ======================== FRONTEND TYPES ========================
cat > apps/web/src/types/hypothesis.ts << 'TSEOF'
export type QuestionType =
  | 'growth_market_entry'
  | 'cost_optimization'
  | 'ma_rationale'
  | 'pricing_strategy'
  | 'competitive_response'
  | 'digital_transformation'
  | 'unknown';

export interface HypothesisNode {
  id: string;
  statement: string;
  parent_id: string | null;
  children: HypothesisNode[];
  depth: number;
  what_must_be_true: string | null;
  evidence_needed: string | null;
  is_leaf: boolean;
}

export interface ClassificationResult {
  question_type: QuestionType;
  framework: string;
  confidence: number;
  rationale: string;
}

export interface HypothesisTree {
  id: string;
  root: HypothesisNode;
  classification: ClassificationResult;
  industry: string;
  company: string;
  question: string;
  created_at: string;
  metadata: Record<string, unknown>;
}
TSEOF

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

# ======================== FRONTEND API CLIENT ========================
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
    request<Project>('/api/projects', {
      method: 'POST',
      body: JSON.stringify(data),
    }),

  generateTree: (projectId: string) =>
    request<Project>(`/api/projects/${projectId}/generate`, {
      method: 'POST',
    }),

  getProject: (projectId: string) =>
    request<Project>(`/api/projects/${projectId}`),

  listProjects: () =>
    request<Project[]>('/api/projects'),
};
TSEOF

# ======================== FRONTEND UTILS ========================
cat > apps/web/src/lib/utils.ts << 'TSEOF'
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export const DEPTH_COLORS = [
  'bg-blue-500',
  'bg-emerald-500',
  'bg-amber-500',
  'bg-purple-500',
] as const;

export function depthColor(depth: number): string {
  return DEPTH_COLORS[depth % DEPTH_COLORS.length] ?? 'bg-gray-500';
}
TSEOF

# ======================== FRONTEND STORE ========================
cat > apps/web/src/stores/projectStore.ts << 'TSEOF'
import { create } from 'zustand';
import type { Project } from '@/types/project';

interface ProjectStore {
  projects: Project[];
  currentProject: Project | null;
  loading: boolean;
  error: string | null;
  setProjects: (projects: Project[]) => void;
  setCurrentProject: (project: Project | null) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  updateProject: (project: Project) => void;
}

export const useProjectStore = create<ProjectStore>((set) => ({
  projects: [],
  currentProject: null,
  loading: false,
  error: null,
  setProjects: (projects) => set({ projects }),
  setCurrentProject: (currentProject) => set({ currentProject }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  updateProject: (project) =>
    set((state) => ({
      projects: state.projects.map((p) => (p.id === project.id ? project : p)),
      currentProject:
        state.currentProject?.id === project.id ? project : state.currentProject,
    })),
}));
TSEOF

# ======================== QUESTION INPUT FORM ========================
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

  return (
    <form onSubmit={handleSubmit} className="space-y-4 max-w-2xl mx-auto">
      <div>
        <label className="block text-sm font-medium text-slate-700 mb-1">Industry</label>
        <input
          type="text"
          value={industry}
          onChange={(e) => setIndustry(e.target.value)}
          placeholder="e.g., Ride-hailing / Mobility"
          className="w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
          disabled={loading}
        />
      </div>
      <div>
        <label className="block text-sm font-medium text-slate-700 mb-1">Company</label>
        <input
          type="text"
          value={company}
          onChange={(e) => setCompany(e.target.value)}
          placeholder="e.g., Grab"
          className="w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
          disabled={loading}
        />
      </div>
      <div>
        <label className="block text-sm font-medium text-slate-700 mb-1">Strategic Question</label>
        <textarea
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder="e.g., Should Grab expand into EV logistics in Vietnam?"
          rows={3}
          className="w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none resize-none"
          disabled={loading}
        />
      </div>
      <button
        type="submit"
        disabled={loading || !industry.trim() || !company.trim() || !question.trim()}
        className="w-full py-2.5 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 disabled:bg-slate-300 disabled:cursor-not-allowed transition-colors"
      >
        {loading ? 'Generating Hypothesis Tree...' : 'Generate Hypothesis Tree'}
      </button>
    </form>
  );
}
TSEOF

# ======================== NODE DETAIL PANEL ========================
cat > apps/web/src/components/tree/NodeDetailPanel.tsx << 'TSEOF'
import type { HypothesisNode } from '@/types/hypothesis';
import { depthColor } from '@/lib/utils';

interface Props {
  node: HypothesisNode | null;
  onClose: () => void;
}

export function NodeDetailPanel({ node, onClose }: Props) {
  if (!node) return null;

  return (
    <div className="fixed right-0 top-0 h-full w-96 bg-white shadow-xl border-l border-slate-200 p-6 overflow-y-auto z-50">
      <div className="flex justify-between items-start mb-4">
        <div className="flex items-center gap-2">
          <div className={`w-3 h-3 rounded-full ${depthColor(node.depth)}`} />
          <span className="text-xs font-mono text-slate-400">Depth {node.depth}</span>
          {node.is_leaf && (
            <span className="text-xs bg-emerald-100 text-emerald-700 px-2 py-0.5 rounded-full">
              Leaf
            </span>
          )}
        </div>
        <button onClick={onClose} className="text-slate-400 hover:text-slate-600 text-xl leading-none">
          &times;
        </button>
      </div>

      <h3 className="text-lg font-semibold text-slate-800 mb-4">{node.statement}</h3>

      {node.what_must_be_true && (
        <div className="mb-4">
          <h4 className="text-sm font-medium text-slate-500 mb-1">What Must Be True</h4>
          <p className="text-sm text-slate-700 bg-slate-50 p-3 rounded-lg">{node.what_must_be_true}</p>
        </div>
      )}

      {node.evidence_needed && (
        <div className="mb-4">
          <h4 className="text-sm font-medium text-slate-500 mb-1">Evidence Needed</h4>
          <p className="text-sm text-slate-700 bg-slate-50 p-3 rounded-lg">{node.evidence_needed}</p>
        </div>
      )}

      <div className="text-xs text-slate-400 mt-6">
        ID: {node.id} &middot; Children: {node.children.length}
      </div>
    </div>
  );
}
TSEOF

# ======================== HYPOTHESIS TREE COMPONENT ========================
cat > apps/web/src/components/tree/HypothesisTree.tsx << 'TSEOF'
import { useState } from 'react';
import type { HypothesisNode as HNode } from '@/types/hypothesis';
import { NodeDetailPanel } from './NodeDetailPanel';
import { depthColor, cn } from '@/lib/utils';

interface TreeNodeProps {
  node: HNode;
  onSelect: (node: HNode) => void;
  selectedId: string | null;
}

function TreeNode({ node, onSelect, selectedId }: TreeNodeProps) {
  const [collapsed, setCollapsed] = useState(false);
  const hasChildren = node.children.length > 0;
  const isSelected = node.id === selectedId;

  return (
    <div className="ml-4 first:ml-0">
      <div
        className={cn(
          'flex items-start gap-2 p-3 rounded-lg mb-1 cursor-pointer transition-all border',
          isSelected
            ? 'border-blue-400 bg-blue-50 shadow-sm'
            : 'border-transparent hover:bg-slate-50'
        )}
        onClick={() => onSelect(node)}
      >
        {hasChildren && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              setCollapsed(!collapsed);
            }}
            className="mt-0.5 text-slate-400 hover:text-slate-600 text-sm flex-shrink-0 w-5 text-center"
          >
            {collapsed ? '▸' : '▾'}
          </button>
        )}
        {!hasChildren && <div className="w-5 flex-shrink-0" />}

        <div className={`w-2 h-2 rounded-full mt-1.5 flex-shrink-0 ${depthColor(node.depth)}`} />

        <div className="min-w-0">
          <p className="text-sm text-slate-800 leading-snug">{node.statement}</p>
          <div className="flex gap-2 mt-1">
            <span className="text-xs text-slate-400 font-mono">d{node.depth}</span>
            {node.is_leaf && (
              <span className="text-xs bg-emerald-100 text-emerald-700 px-1.5 rounded">leaf</span>
            )}
          </div>
        </div>
      </div>

      {hasChildren && !collapsed && (
        <div className="border-l-2 border-slate-200 ml-6">
          {node.children.map((child) => (
            <TreeNode key={child.id} node={child} onSelect={onSelect} selectedId={selectedId} />
          ))}
        </div>
      )}
    </div>
  );
}

interface Props {
  root: HNode;
}

export function HypothesisTreeView({ root }: Props) {
  const [selected, setSelected] = useState<HNode | null>(null);

  return (
    <div className="flex">
      <div className="flex-1 p-4">
        <TreeNode node={root} onSelect={setSelected} selectedId={selected?.id ?? null} />
      </div>
      <NodeDetailPanel node={selected} onClose={() => setSelected(null)} />
    </div>
  );
}
TSEOF

# ======================== LOADING STATE ========================
cat > apps/web/src/components/common/LoadingState.tsx << 'TSEOF'
const STEPS = [
  'Classifying question type...',
  'Selecting decomposition framework...',
  'Generating root hypothesis...',
  'Decomposing into sub-hypotheses...',
  'Validating MECE structure...',
  'Finalizing hypothesis tree...',
];

export function LoadingState() {
  return (
    <div className="flex flex-col items-center justify-center py-16">
      <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin mb-6" />
      <div className="space-y-2 text-center">
        {STEPS.map((step, i) => (
          <p key={i} className="text-sm text-slate-500 animate-pulse" style={{ animationDelay: `${i * 0.3}s` }}>
            {step}
          </p>
        ))}
      </div>
      <p className="text-xs text-slate-400 mt-6">This typically takes 30-60 seconds</p>
    </div>
  );
}
TSEOF

# ======================== ERROR BOUNDARY ========================
cat > apps/web/src/components/common/ErrorBoundary.tsx << 'TSEOF'
import { Component, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  render() {
    if (this.state.hasError) {
      return (
        this.props.fallback ?? (
          <div className="p-8 text-center">
            <h2 className="text-lg font-semibold text-red-600 mb-2">Something went wrong</h2>
            <p className="text-sm text-slate-600">{this.state.error?.message}</p>
            <button
              onClick={() => this.setState({ hasError: false, error: null })}
              className="mt-4 px-4 py-2 bg-slate-100 rounded-lg text-sm hover:bg-slate-200"
            >
              Try again
            </button>
          </div>
        )
      );
    }
    return this.props.children;
  }
}
TSEOF

# ======================== APP.TSX ========================
cat > apps/web/src/App.tsx << 'TSEOF'
import { useState } from 'react';
import { QuestionInput } from '@/components/forms/QuestionInput';
import { HypothesisTreeView } from '@/components/tree/HypothesisTree';
import { LoadingState } from '@/components/common/LoadingState';
import { ErrorBoundary } from '@/components/common/ErrorBoundary';
import { api } from '@/lib/api';
import type { Project, ProjectCreate } from '@/types/project';

function App() {
  const [project, setProject] = useState<Project | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

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

  const handleReset = () => {
    setProject(null);
    setError(null);
  };

  return (
    <ErrorBoundary>
      <div className="min-h-screen bg-slate-50">
        <header className="bg-white border-b border-slate-200 px-6 py-4">
          <div className="flex items-center justify-between max-w-7xl mx-auto">
            <h1
              className="text-xl font-bold text-slate-800 cursor-pointer"
              onClick={handleReset}
            >
              HypoTree
            </h1>
            {project && (
              <button
                onClick={handleReset}
                className="text-sm text-blue-600 hover:text-blue-700"
              >
                New Question
              </button>
            )}
          </div>
        </header>

        <main className="max-w-7xl mx-auto py-8 px-6">
          {error && (
            <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">
              {error}
            </div>
          )}

          {loading && <LoadingState />}

          {!loading && !project && <QuestionInput onSubmit={handleSubmit} loading={loading} />}

          {!loading && project?.tree && (
            <div>
              <div className="mb-6 p-4 bg-white rounded-lg border border-slate-200">
                <div className="flex items-center gap-4 text-sm text-slate-600">
                  <span>
                    <strong>Industry:</strong> {project.industry}
                  </span>
                  <span>
                    <strong>Company:</strong> {project.company}
                  </span>
                  <span>
                    <strong>Type:</strong>{' '}
                    {project.tree.classification.question_type.replace(/_/g, ' ')}
                  </span>
                  <span>
                    <strong>Framework:</strong>{' '}
                    {project.tree.classification.framework.replace(/_/g, ' ')}
                  </span>
                  <span>
                    <strong>Confidence:</strong>{' '}
                    {(project.tree.classification.confidence * 100).toFixed(0)}%
                  </span>
                </div>
                <p className="text-sm text-slate-500 mt-2">{project.question}</p>
              </div>
              <HypothesisTreeView root={project.tree.root} />
            </div>
          )}
        </main>
      </div>
    </ErrorBoundary>
  );
}

export default App;
TSEOF

# ======================== BACKEND TESTS ========================
cat > apps/api/tests/conftest.py << 'PYEOF'
import os
import sys

# Add project root to path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)
PYEOF

cat > apps/api/tests/test_tree_generation.py << 'PYEOF'
"""Phase 1 tests — run with: cd apps/api && source .venv/bin/activate && python -m pytest tests/ -v"""
import os
import sys

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from packages.shared.types import HypothesisNode, QuestionType


def test_hypothesis_node_creation():
    node = HypothesisNode(statement="Test hypothesis", depth=0)
    assert node.statement == "Test hypothesis"
    assert node.depth == 0
    assert node.children == []
    assert node.is_leaf is False
    assert node.id is not None


def test_hypothesis_node_tree_structure():
    root = HypothesisNode(statement="Root", depth=0)
    child1 = HypothesisNode(statement="Child 1", depth=1, parent_id=root.id)
    child2 = HypothesisNode(statement="Child 2", depth=1, parent_id=root.id)
    root.children = [child1, child2]

    assert len(root.children) == 2
    assert root.children[0].statement == "Child 1"
    assert root.children[1].parent_id == root.id


def test_question_types():
    assert QuestionType.GROWTH_MARKET_ENTRY.value == "growth_market_entry"
    assert QuestionType.COST_OPTIMIZATION.value == "cost_optimization"
    assert len(QuestionType) == 7  # 6 types + unknown
PYEOF

echo ""
echo "=== Phase 1 files written ==="
echo ""
echo "To test backend (unit tests, no API key needed):"
echo "  cd apps/api && source .venv/bin/activate && python -m pytest tests/ -v"
echo ""
echo "To run full system (requires ANTHROPIC_API_KEY in apps/api/.env):"
echo "  Terminal 1: cd apps/api && source .venv/bin/activate && uvicorn app.main:app --reload --port 8000"
echo "  Terminal 2: cd apps/web && npm run dev"
echo "  Open http://localhost:5173"
echo ""
echo "To test API directly:"
echo '  curl -X POST http://localhost:8000/api/projects -H "Content-Type: application/json" -d '\''{"industry":"Ride-hailing","company":"Grab","question":"Should Grab expand into EV logistics in Vietnam?"}'\'''
echo "  # Copy the id from response, then:"
echo '  curl -X POST http://localhost:8000/api/projects/<ID>/generate'