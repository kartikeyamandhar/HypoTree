#!/bin/bash
set -e

# ============================================================
# HypoTree Phase 2 — Testability Classification + Analysis Design
# Run from hypotree/ root
# Usage: bash phase2.sh
# ============================================================

echo "=== Phase 2: Testability Classification + Analysis Design ==="

# ======================== SHARED TYPES — add testability + analysis models ========================
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

# ======================== TESTABILITY CLASSIFIER PROMPTS ========================
cat > packages/agents/testability_classifier/prompts.py << 'PYEOF'
TESTABILITY_PROMPT = """You are a strategy consulting analyst classifying the testability of hypotheses.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

For the following leaf hypothesis, classify its testability and assign priority scores.

Hypothesis: "{statement}"
What must be true: "{what_must_be_true}"
Evidence needed: "{evidence_needed}"

Classifications:
- quantitative: Can be tested with data analysis (market data, financials, surveys, metrics)
- qualitative: Requires expert interviews, primary research, or qualitative judgment
- assumption: Requires team alignment or client input; not externally verifiable
- already_answered: Public data exists that resolves this hypothesis now

Scoring:
- impact_score (1-5): How much does this hypothesis matter to the overall answer?
- testability_score (1-3): How feasible is it to test this hypothesis? 3=easy, 1=hard
- data_availability_score (1-3): How available is the needed data? 3=public, 1=proprietary/unavailable

Respond ONLY with valid JSON, no markdown fences:
{{
  "classification": "<quantitative|qualitative|assumption|already_answered>",
  "confidence": <0.0-1.0>,
  "rationale": "<one sentence explaining classification>",
  "impact_score": <1-5>,
  "testability_score": <1-3>,
  "data_availability_score": <1-3>
}}"""
PYEOF

# ======================== TESTABILITY CLASSIFIER AGENT ========================
cat > packages/agents/testability_classifier/agent.py << 'PYEOF'
"""Testability Classifier agent — tags each leaf hypothesis with testability class + priority score."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.testability_classifier.prompts import TESTABILITY_PROMPT
from packages.shared.types import HypothesisNode, TestabilityClass, TestabilityResult

logger = logging.getLogger(__name__)


class TestabilityClassifierAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a strategy consulting analyst specializing in hypothesis testability assessment."

    def classify(
        self,
        node: HypothesisNode,
        industry: str,
        company: str,
        question: str,
    ) -> TestabilityResult:
        prompt = TESTABILITY_PROMPT.format(
            industry=industry,
            company=company,
            question=question,
            statement=node.statement,
            what_must_be_true=node.what_must_be_true or "Not specified",
            evidence_needed=node.evidence_needed or "Not specified",
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        result = TestabilityResult(
            classification=TestabilityClass(data["classification"]),
            confidence=data.get("confidence", 0.8),
            rationale=data.get("rationale", ""),
            impact_score=max(1, min(5, data.get("impact_score", 3))),
            testability_score=max(1, min(3, data.get("testability_score", 2))),
            data_availability_score=max(1, min(3, data.get("data_availability_score", 2))),
        )

        logger.info(
            "Classified '%s': %s (impact=%d test=%d data=%d priority=%.0f)",
            node.statement[:50],
            result.classification.value,
            result.impact_score,
            result.testability_score,
            result.data_availability_score,
            result.priority_score,
        )
        return result
PYEOF

# ======================== ANALYSIS DESIGNER PROMPTS ========================
cat > packages/agents/analysis_designer/prompts.py << 'PYEOF'
ANALYSIS_DESIGN_PROMPT = """You are a strategy consulting analyst designing analysis methodologies.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

For the following hypothesis classified as "{testability_class}", design an appropriate analysis.

Hypothesis: "{statement}"
What must be true: "{what_must_be_true}"
Evidence needed: "{evidence_needed}"

Available analysis types:
- regression: Statistical regression on historical data
- benchmarking: Compare against industry peers or best practices
- cohort_analysis: Segment-based analysis of customer or market groups
- scenario_modeling: Build scenarios with different assumptions
- break_even: Determine threshold values for viability
- market_sizing: Top-down or bottom-up market size estimation
- competitive_analysis: Analyze competitor positioning and responses
- financial_modeling: Build financial projections (DCF, multiples, etc.)
- survey_analysis: Design and analyze primary research surveys
- expert_interviews: Structure and synthesize expert interview findings
- case_study: Analyze analogous historical cases
- data_analysis: General quantitative analysis of available datasets
- cost_analysis: Detailed cost structure and optimization analysis
- sensitivity_analysis: Test sensitivity of conclusions to key assumptions

Choose the MOST appropriate analysis type. Do NOT choose expert_interviews or survey_analysis for quantitative hypotheses. Do NOT choose regression or financial_modeling for qualitative hypotheses.

For data_sources, list 3-5 specific, realistic sources (e.g., "SEC 10-K filings", "Euromonitor travel market reports", "SimilarWeb traffic data").

For loe_hours, estimate realistic analyst-hours: simple analyses 4-8h, moderate 8-20h, complex 20-40h.

Respond ONLY with valid JSON, no markdown fences:
{{
  "analysis_type": "<type>",
  "methodology": "<2-3 sentence description of specific analytical approach>",
  "data_sources": ["<source1>", "<source2>", "<source3>"],
  "output_format": "<chart type or deliverable format, e.g., 'Waterfall chart showing synergy breakdown'>",
  "loe_hours": <number>,
  "rationale": "<one sentence on why this analysis type fits>"
}}"""
PYEOF

# ======================== ANALYSIS DESIGNER AGENT ========================
cat > packages/agents/analysis_designer/agent.py << 'PYEOF'
"""Analysis Designer agent — proposes methodology per testable hypothesis."""
from __future__ import annotations

import json
import logging

from packages.agents.base import BaseAgent
from packages.agents.analysis_designer.prompts import ANALYSIS_DESIGN_PROMPT
from packages.shared.types import AnalysisDesign, AnalysisType, HypothesisNode, TestabilityResult

logger = logging.getLogger(__name__)


class AnalysisDesignerAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are a strategy consulting analyst specializing in analysis design and methodology."

    def design(
        self,
        node: HypothesisNode,
        testability: TestabilityResult,
        industry: str,
        company: str,
        question: str,
    ) -> AnalysisDesign:
        prompt = ANALYSIS_DESIGN_PROMPT.format(
            industry=industry,
            company=company,
            question=question,
            testability_class=testability.classification.value,
            statement=node.statement,
            what_must_be_true=node.what_must_be_true or "Not specified",
            evidence_needed=node.evidence_needed or "Not specified",
        )

        raw = self.call_llm(prompt)
        data = json.loads(raw)

        # Safely parse analysis_type
        try:
            analysis_type = AnalysisType(data["analysis_type"])
        except ValueError:
            analysis_type = AnalysisType.DATA_ANALYSIS

        result = AnalysisDesign(
            analysis_type=analysis_type,
            methodology=data.get("methodology", ""),
            data_sources=data.get("data_sources", []),
            output_format=data.get("output_format", ""),
            loe_hours=data.get("loe_hours", 8.0),
            rationale=data.get("rationale", ""),
        )

        logger.info(
            "Designed analysis for '%s': %s (%.0fh LOE)",
            node.statement[:50],
            result.analysis_type.value,
            result.loe_hours,
        )
        return result
PYEOF

# ======================== UPDATE ORCHESTRATOR — add Phase 2 pipeline ========================
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
from packages.agents.orchestrator.prompts import CLASSIFICATION_PROMPT, ROOT_HYPOTHESIS_PROMPT
from packages.shared.constants import MECE_MAX_RETRIES, ORCHESTRATOR_MODEL, TARGET_TREE_DEPTH
from packages.shared.types import (
    ClassificationResult,
    Framework,
    HypothesisNode,
    HypothesisTree,
    QuestionType,
    TestabilityClass,
)

logger = logging.getLogger(__name__)


class OrchestratorAgent(BaseAgent):
    def __init__(self) -> None:
        super().__init__(model=ORCHESTRATOR_MODEL)
        self.decomposer = DecomposerAgent()
        self.mece_validator = MECEValidatorAgent()
        self.testability_classifier = TestabilityClassifierAgent()
        self.analysis_designer = AnalysisDesignerAgent()

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

    def _decompose_with_validation(
        self,
        node: HypothesisNode,
        industry: str,
        company: str,
        question: str,
    ) -> list[HypothesisNode]:
        children = self.decomposer.decompose(
            parent=node, industry=industry, company=company, question=question,
        )

        best_children = children
        best_score = 999

        for attempt in range(MECE_MAX_RETRIES):
            validation = self.mece_validator.validate(parent=node, children=children)
            score = len(validation.overlaps) + len(validation.gaps)

            if score < best_score:
                best_score = score
                best_children = children

            if validation.is_valid:
                logger.info("MECE passed on attempt %d for '%s'", attempt + 1, node.statement[:50])
                return children

            logger.info(
                "MECE attempt %d/%d for '%s': overlaps=%d gaps=%d",
                attempt + 1, MECE_MAX_RETRIES, node.statement[:50],
                len(validation.overlaps), len(validation.gaps),
            )

            if attempt < MECE_MAX_RETRIES - 1:
                children = self.decomposer.decompose(
                    parent=node, industry=industry, company=company,
                    question=question, previous_issues=validation,
                )

        logger.warning(
            "MECE exhausted retries for '%s'. Accepting best (score=%d).",
            node.statement[:50], best_score,
        )
        return best_children

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
            children = self._decompose_with_validation(node, industry, company, question)
            for child in children:
                child.parent_id = node.id
                child.depth = node.depth + 1
                node.children.append(child)

        for child in node.children:
            self._decompose_recursive(child, industry, company, question, target_depth)

    def _classify_and_design(
        self,
        node: HypothesisNode,
        industry: str,
        company: str,
        question: str,
    ) -> None:
        """Phase 2: classify testability and design analysis for each leaf."""
        if not node.is_leaf:
            for child in node.children:
                self._classify_and_design(child, industry, company, question)
            return

        # Step 1: Classify testability
        testability = self.testability_classifier.classify(
            node=node, industry=industry, company=company, question=question,
        )
        node.testability = testability

        # Step 2: Design analysis (skip for assumption-based unless high impact)
        if testability.classification != TestabilityClass.ASSUMPTION or testability.impact_score >= 4:
            analysis = self.analysis_designer.design(
                node=node,
                testability=testability,
                industry=industry,
                company=company,
                question=question,
            )
            node.analysis = analysis

    def generate_tree(self, industry: str, company: str, question: str) -> HypothesisTree:
        logger.info("Starting tree generation: %s / %s / %s", industry, company, question)

        # Phase 1: Classification
        classification = self.classify_question(industry, company, question)
        logger.info("Classification: %s (%.2f)", classification.question_type, classification.confidence)

        # Phase 1: Root + decomposition
        root = self.generate_root_and_branches(industry, company, question, classification)
        logger.info("Root generated with %d first-level branches", len(root.children))

        self._decompose_recursive(root, industry, company, question, TARGET_TREE_DEPTH)

        all_nodes = self._collect_all(root)
        leaf_count = len([n for n in all_nodes if n.is_leaf])
        logger.info("Decomposition complete: %d nodes, %d leaves", len(all_nodes), leaf_count)

        # Phase 2: Testability + Analysis Design
        logger.info("Starting testability classification and analysis design...")
        self._classify_and_design(root, industry, company, question)

        classified = [n for n in all_nodes if n.testability is not None]
        logger.info("Phase 2 complete: %d leaves classified", len(classified))

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

# ======================== FRONTEND TYPES — add testability + analysis ========================
cat > apps/web/src/types/hypothesis.ts << 'TSEOF'
export type QuestionType =
  | 'growth_market_entry'
  | 'cost_optimization'
  | 'ma_rationale'
  | 'pricing_strategy'
  | 'competitive_response'
  | 'digital_transformation'
  | 'unknown';

export type TestabilityClass =
  | 'quantitative'
  | 'qualitative'
  | 'assumption'
  | 'already_answered';

export type AnalysisType =
  | 'regression'
  | 'benchmarking'
  | 'cohort_analysis'
  | 'scenario_modeling'
  | 'break_even'
  | 'market_sizing'
  | 'competitive_analysis'
  | 'financial_modeling'
  | 'survey_analysis'
  | 'expert_interviews'
  | 'case_study'
  | 'data_analysis'
  | 'cost_analysis'
  | 'sensitivity_analysis';

export interface TestabilityResult {
  classification: TestabilityClass;
  confidence: number;
  rationale: string;
  impact_score: number;
  testability_score: number;
  data_availability_score: number;
  priority_score?: number;
}

export interface AnalysisDesign {
  analysis_type: AnalysisType;
  methodology: string;
  data_sources: string[];
  output_format: string;
  loe_hours: number;
  rationale: string;
}

export interface HypothesisNode {
  id: string;
  statement: string;
  parent_id: string | null;
  children: HypothesisNode[];
  depth: number;
  what_must_be_true: string | null;
  evidence_needed: string | null;
  is_leaf: boolean;
  testability: TestabilityResult | null;
  analysis: AnalysisDesign | null;
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

# ======================== ANALYSIS TYPES — for analysis plan table ========================
cat > apps/web/src/types/analysis.ts << 'TSEOF'
import type { HypothesisNode } from './hypothesis';

export interface AnalysisPlanRow {
  node: HypothesisNode;
  priorityScore: number;
}

export function getAnalysisPlanRows(root: HypothesisNode): AnalysisPlanRow[] {
  const rows: AnalysisPlanRow[] = [];

  function walk(node: HypothesisNode) {
    if (node.is_leaf && node.testability) {
      const priority =
        node.testability.impact_score *
        node.testability.testability_score *
        node.testability.data_availability_score;
      rows.push({ node, priorityScore: priority });
    }
    for (const child of node.children) {
      walk(child);
    }
  }

  walk(root);
  return rows.sort((a, b) => b.priorityScore - a.priorityScore);
}
TSEOF

# ======================== FRONTEND UTILS — add testability colors ========================
cat > apps/web/src/lib/utils.ts << 'TSEOF'
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import type { TestabilityClass } from '@/types/hypothesis';

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

export const TESTABILITY_COLORS: Record<TestabilityClass, { bg: string; text: string; label: string }> = {
  quantitative: { bg: 'bg-green-100', text: 'text-green-700', label: 'Quantitative' },
  qualitative: { bg: 'bg-blue-100', text: 'text-blue-700', label: 'Qualitative' },
  assumption: { bg: 'bg-yellow-100', text: 'text-yellow-700', label: 'Assumption' },
  already_answered: { bg: 'bg-purple-100', text: 'text-purple-700', label: 'Already Answered' },
};

export function testabilityColor(tc: TestabilityClass) {
  return TESTABILITY_COLORS[tc] ?? { bg: 'bg-gray-100', text: 'text-gray-700', label: tc };
}
TSEOF

# ======================== TESTABILITY BADGE COMPONENT ========================
cat > apps/web/src/components/analysis/TestabilityBadge.tsx << 'TSEOF'
import type { TestabilityClass } from '@/types/hypothesis';
import { testabilityColor, cn } from '@/lib/utils';

interface Props {
  classification: TestabilityClass;
  className?: string;
}

export function TestabilityBadge({ classification, className }: Props) {
  const color = testabilityColor(classification);
  return (
    <span className={cn('text-xs px-2 py-0.5 rounded-full font-medium', color.bg, color.text, className)}>
      {color.label}
    </span>
  );
}
TSEOF

# ======================== ANALYSIS PLAN TABLE COMPONENT ========================
cat > apps/web/src/components/analysis/AnalysisPlanTable.tsx << 'TSEOF'
import { useState, useMemo } from 'react';
import type { HypothesisNode, TestabilityClass } from '@/types/hypothesis';
import { getAnalysisPlanRows } from '@/types/analysis';
import { TestabilityBadge } from './TestabilityBadge';

interface Props {
  root: HypothesisNode;
}

type SortField = 'priority' | 'loe' | 'impact' | 'type';

export function AnalysisPlanTable({ root }: Props) {
  const [sortField, setSortField] = useState<SortField>('priority');
  const [filterClass, setFilterClass] = useState<TestabilityClass | 'all'>('all');

  const rows = useMemo(() => {
    let r = getAnalysisPlanRows(root);

    if (filterClass !== 'all') {
      r = r.filter((row) => row.node.testability?.classification === filterClass);
    }

    r.sort((a, b) => {
      switch (sortField) {
        case 'priority':
          return b.priorityScore - a.priorityScore;
        case 'loe':
          return (a.node.analysis?.loe_hours ?? 0) - (b.node.analysis?.loe_hours ?? 0);
        case 'impact':
          return (b.node.testability?.impact_score ?? 0) - (a.node.testability?.impact_score ?? 0);
        case 'type':
          return (a.node.testability?.classification ?? '').localeCompare(
            b.node.testability?.classification ?? ''
          );
        default:
          return 0;
      }
    });

    return r;
  }, [root, sortField, filterClass]);

  const totalLOE = rows.reduce((sum, r) => sum + (r.node.analysis?.loe_hours ?? 0), 0);

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-slate-800">
          Analysis Plan ({rows.length} hypotheses, {totalLOE.toFixed(0)}h total LOE)
        </h3>
        <div className="flex gap-2">
          <select
            value={filterClass}
            onChange={(e) => setFilterClass(e.target.value as TestabilityClass | 'all')}
            className="text-sm border border-slate-300 rounded-lg px-2 py-1"
          >
            <option value="all">All Types</option>
            <option value="quantitative">Quantitative</option>
            <option value="qualitative">Qualitative</option>
            <option value="assumption">Assumption</option>
            <option value="already_answered">Already Answered</option>
          </select>
          <select
            value={sortField}
            onChange={(e) => setSortField(e.target.value as SortField)}
            className="text-sm border border-slate-300 rounded-lg px-2 py-1"
          >
            <option value="priority">Sort: Priority</option>
            <option value="loe">Sort: LOE</option>
            <option value="impact">Sort: Impact</option>
            <option value="type">Sort: Type</option>
          </select>
        </div>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-slate-200 text-left text-slate-500">
              <th className="pb-2 pr-4 font-medium">#</th>
              <th className="pb-2 pr-4 font-medium">Hypothesis</th>
              <th className="pb-2 pr-4 font-medium">Class</th>
              <th className="pb-2 pr-4 font-medium">Priority</th>
              <th className="pb-2 pr-4 font-medium">Analysis</th>
              <th className="pb-2 pr-4 font-medium">Data Sources</th>
              <th className="pb-2 pr-4 font-medium">Output</th>
              <th className="pb-2 pr-4 font-medium">LOE</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, i) => (
              <tr key={row.node.id} className="border-b border-slate-100 hover:bg-slate-50">
                <td className="py-3 pr-4 text-slate-400">{i + 1}</td>
                <td className="py-3 pr-4 max-w-xs">
                  <p className="text-slate-800 leading-snug">{row.node.statement}</p>
                </td>
                <td className="py-3 pr-4">
                  {row.node.testability && (
                    <TestabilityBadge classification={row.node.testability.classification} />
                  )}
                </td>
                <td className="py-3 pr-4">
                  <span className="font-mono text-slate-600">{row.priorityScore}</span>
                </td>
                <td className="py-3 pr-4">
                  {row.node.analysis && (
                    <div>
                      <p className="font-medium text-slate-700">
                        {row.node.analysis.analysis_type.replace(/_/g, ' ')}
                      </p>
                      <p className="text-xs text-slate-500 mt-0.5">{row.node.analysis.methodology}</p>
                    </div>
                  )}
                </td>
                <td className="py-3 pr-4">
                  {row.node.analysis?.data_sources.map((src, j) => (
                    <span
                      key={j}
                      className="inline-block text-xs bg-slate-100 text-slate-600 px-1.5 py-0.5 rounded mr-1 mb-1"
                    >
                      {src}
                    </span>
                  ))}
                </td>
                <td className="py-3 pr-4 text-xs text-slate-600">
                  {row.node.analysis?.output_format}
                </td>
                <td className="py-3 pr-4 font-mono text-slate-600">
                  {row.node.analysis?.loe_hours ?? '-'}h
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
TSEOF

# ======================== UPDATED NODE DETAIL PANEL — show testability + analysis ========================
cat > apps/web/src/components/tree/NodeDetailPanel.tsx << 'TSEOF'
import type { HypothesisNode } from '@/types/hypothesis';
import { depthColor } from '@/lib/utils';
import { TestabilityBadge } from '@/components/analysis/TestabilityBadge';

interface Props {
  node: HypothesisNode | null;
  onClose: () => void;
}

export function NodeDetailPanel({ node, onClose }: Props) {
  if (!node) return null;

  const priority = node.testability
    ? node.testability.impact_score *
      node.testability.testability_score *
      node.testability.data_availability_score
    : null;

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

      {node.testability && (
        <div className="mb-4 p-3 bg-slate-50 rounded-lg">
          <div className="flex items-center justify-between mb-2">
            <h4 className="text-sm font-medium text-slate-500">Testability</h4>
            <TestabilityBadge classification={node.testability.classification} />
          </div>
          <p className="text-sm text-slate-600 mb-2">{node.testability.rationale}</p>
          <div className="grid grid-cols-3 gap-2 text-center">
            <div>
              <p className="text-xs text-slate-400">Impact</p>
              <p className="text-sm font-semibold text-slate-700">{node.testability.impact_score}/5</p>
            </div>
            <div>
              <p className="text-xs text-slate-400">Testability</p>
              <p className="text-sm font-semibold text-slate-700">{node.testability.testability_score}/3</p>
            </div>
            <div>
              <p className="text-xs text-slate-400">Data Avail.</p>
              <p className="text-sm font-semibold text-slate-700">{node.testability.data_availability_score}/3</p>
            </div>
          </div>
          {priority !== null && (
            <p className="text-xs text-slate-400 mt-2 text-center">Priority Score: {priority}</p>
          )}
        </div>
      )}

      {node.analysis && (
        <div className="mb-4 p-3 bg-blue-50 rounded-lg">
          <h4 className="text-sm font-medium text-slate-500 mb-2">Proposed Analysis</h4>
          <p className="text-sm font-semibold text-slate-700 mb-1">
            {node.analysis.analysis_type.replace(/_/g, ' ')}
          </p>
          <p className="text-sm text-slate-600 mb-2">{node.analysis.methodology}</p>

          <div className="mb-2">
            <p className="text-xs font-medium text-slate-500 mb-1">Data Sources</p>
            <div className="flex flex-wrap gap-1">
              {node.analysis.data_sources.map((src, i) => (
                <span key={i} className="text-xs bg-white text-slate-600 px-1.5 py-0.5 rounded border border-slate-200">
                  {src}
                </span>
              ))}
            </div>
          </div>

          <div className="flex justify-between text-xs text-slate-500 mt-2">
            <span>Output: {node.analysis.output_format}</span>
            <span>LOE: {node.analysis.loe_hours}h</span>
          </div>
        </div>
      )}

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

# ======================== UPDATED TREE VIEW — testability color badges ========================
cat > apps/web/src/components/tree/HypothesisTree.tsx << 'TSEOF'
import { useState } from 'react';
import type { HypothesisNode as HNode } from '@/types/hypothesis';
import { NodeDetailPanel } from './NodeDetailPanel';
import { TestabilityBadge } from '@/components/analysis/TestabilityBadge';
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
            {collapsed ? '\u25B8' : '\u25BE'}
          </button>
        )}
        {!hasChildren && <div className="w-5 flex-shrink-0" />}

        <div className={`w-2 h-2 rounded-full mt-1.5 flex-shrink-0 ${depthColor(node.depth)}`} />

        <div className="min-w-0 flex-1">
          <p className="text-sm text-slate-800 leading-snug">{node.statement}</p>
          <div className="flex gap-2 mt-1 items-center">
            <span className="text-xs text-slate-400 font-mono">d{node.depth}</span>
            {node.is_leaf && (
              <span className="text-xs bg-emerald-100 text-emerald-700 px-1.5 rounded">leaf</span>
            )}
            {node.testability && (
              <TestabilityBadge classification={node.testability.classification} />
            )}
            {node.analysis && (
              <span className="text-xs bg-slate-100 text-slate-500 px-1.5 rounded">
                {node.analysis.analysis_type.replace(/_/g, ' ')}
              </span>
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

# ======================== UPDATED APP.TSX — add view toggle for tree vs table ========================
cat > apps/web/src/App.tsx << 'TSEOF'
import { useState } from 'react';
import { QuestionInput } from '@/components/forms/QuestionInput';
import { HypothesisTreeView } from '@/components/tree/HypothesisTree';
import { AnalysisPlanTable } from '@/components/analysis/AnalysisPlanTable';
import { LoadingState } from '@/components/common/LoadingState';
import { ErrorBoundary } from '@/components/common/ErrorBoundary';
import { api } from '@/lib/api';
import type { Project, ProjectCreate } from '@/types/project';

type ViewMode = 'tree' | 'table';

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

  const handleReset = () => {
    setProject(null);
    setError(null);
    setViewMode('tree');
  };

  return (
    <ErrorBoundary>
      <div className="min-h-screen bg-slate-50">
        <header className="bg-white border-b border-slate-200 px-6 py-4">
          <div className="flex items-center justify-between max-w-7xl mx-auto">
            <h1 className="text-xl font-bold text-slate-800 cursor-pointer" onClick={handleReset}>
              HypoTree
            </h1>
            <div className="flex items-center gap-4">
              {project?.tree && (
                <div className="flex bg-slate-100 rounded-lg p-0.5">
                  <button
                    onClick={() => setViewMode('tree')}
                    className={`px-3 py-1 text-sm rounded-md transition-colors ${
                      viewMode === 'tree'
                        ? 'bg-white text-slate-800 shadow-sm'
                        : 'text-slate-500 hover:text-slate-700'
                    }`}
                  >
                    Tree View
                  </button>
                  <button
                    onClick={() => setViewMode('table')}
                    className={`px-3 py-1 text-sm rounded-md transition-colors ${
                      viewMode === 'table'
                        ? 'bg-white text-slate-800 shadow-sm'
                        : 'text-slate-500 hover:text-slate-700'
                    }`}
                  >
                    Analysis Plan
                  </button>
                </div>
              )}
              {project && (
                <button onClick={handleReset} className="text-sm text-blue-600 hover:text-blue-700">
                  New Question
                </button>
              )}
            </div>
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
            </div>
          )}
        </main>
      </div>
    </ErrorBoundary>
  );
}

export default App;
TSEOF

# ======================== UPDATED LOADING STATE ========================
cat > apps/web/src/components/common/LoadingState.tsx << 'TSEOF'
const STEPS = [
  'Classifying question type...',
  'Selecting decomposition framework...',
  'Generating root hypothesis...',
  'Decomposing into sub-hypotheses...',
  'Validating MECE structure...',
  'Classifying testability of leaves...',
  'Designing analysis methodologies...',
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
      <p className="text-xs text-slate-400 mt-6">This typically takes 2-4 minutes with analysis design</p>
    </div>
  );
}
TSEOF

echo ""
echo "=== Phase 2 files written ==="
echo ""
echo "Restart backend (uvicorn will auto-reload if watching)."
echo "Frontend hot-reloads automatically."
echo ""
echo "New features:"
echo "  - Each leaf node now has a testability classification (quantitative/qualitative/assumption/already_answered)"
echo "  - Each leaf has a proposed analysis with methodology, data sources, output format, LOE"
echo "  - Tree view shows colored testability badges on each leaf"
echo "  - 'Analysis Plan' tab shows sortable/filterable table of all classified hypotheses"
echo "  - Node detail panel now shows testability scores and full analysis design"
echo ""
echo "Test: generate a new tree and toggle between Tree View and Analysis Plan."