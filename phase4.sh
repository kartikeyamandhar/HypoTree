#!/bin/bash
set -e

# ============================================================
# HypoTree Phase 4 — Adversarial Stress-Testing
# Run from hypotree/ root
# Usage: bash phase4.sh
# ============================================================

echo "=== Phase 4: Adversarial Stress-Testing ==="

# ======================== SHARED TYPES — add stress test models ========================
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

# ======================== RED TEAM PROMPTS ========================
cat > packages/agents/red_team/prompts.py << 'PYEOF'
DEVILS_ADVOCATE_PROMPT = """You are a Red Team analyst performing adversarial critique of a strategy hypothesis tree.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

For each of the following high-impact leaf hypotheses, generate the STRONGEST possible counterargument. Ground it in evidence, logic, or analogous cases. Do not be generic.

Hypotheses to challenge:
{hypotheses_block}

Respond ONLY with valid JSON, no markdown fences:
{{
  "critiques": [
    {{
      "target_node_id": "<id>",
      "severity": "<critical|warning|note>",
      "claim_challenged": "<what specific claim you are attacking>",
      "evidence_basis": "<concrete evidence, analogy, or logical argument against it>",
      "suggested_resolution": "<how the team could address this concern>"
    }}
  ]
}}"""

ASSUMPTION_SURFACER_PROMPT = """You are a Red Team analyst identifying hidden assumptions in a strategy hypothesis tree.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

The following hypotheses contain implicit assumptions that are NOT stated. Your job is to make the implicit explicit.

Hypotheses:
{hypotheses_block}

For each hypothesis, identify 1-2 hidden assumptions the analyst did NOT explicitly state. Rate each by fragility (how likely is this assumption to be wrong).

Respond ONLY with valid JSON, no markdown fences:
{{
  "critiques": [
    {{
      "target_node_id": "<id>",
      "severity": "<critical|warning|note>",
      "claim_challenged": "<the hidden assumption you identified>",
      "evidence_basis": "<why this assumption might be wrong>",
      "suggested_resolution": "<how to validate or mitigate this assumption>"
    }}
  ]
}}"""

SENSITIVITY_PROMPT = """You are a Red Team analyst performing sensitivity analysis on quantitative hypotheses.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

For each hypothesis below that contains a quantitative claim or threshold, identify:
1. The key variable the conclusion depends on
2. The breakpoint where the conclusion would flip
3. How sensitive the overall conclusion is to this variable

Hypotheses with data:
{hypotheses_block}

Respond ONLY with valid JSON, no markdown fences:
{{
  "critiques": [
    {{
      "target_node_id": "<id>",
      "severity": "<critical|warning|note>",
      "claim_challenged": "<the quantitative claim>",
      "evidence_basis": "<the sensitivity analysis>",
      "breakpoint_info": "<e.g., 'Conclusion holds if growth > 8%. Below 6%, opposite conclusion follows.'>",
      "suggested_resolution": "<what analysis would resolve the uncertainty>"
    }}
  ]
}}"""

CONTRADICTION_PROMPT = """You are a Red Team analyst scanning for internal contradictions in a strategy hypothesis tree.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

Scan the following pairs of hypotheses for contradictions. A contradiction exists when two hypotheses make conflicting assumptions about the same variable, market condition, or causal relationship.

Hypothesis pairs to check:
{pairs_block}

Respond ONLY with valid JSON, no markdown fences:
{{
  "critiques": [
    {{
      "target_node_id": "<id of first hypothesis>",
      "related_node_id": "<id of second hypothesis>",
      "severity": "<critical|warning|note>",
      "claim_challenged": "<the contradiction>",
      "evidence_basis": "<why these two claims conflict>",
      "suggested_resolution": "<how to resolve the contradiction>"
    }}
  ]
}}

If no contradictions are found, return: {{"critiques": []}}"""
PYEOF

# ======================== RED TEAM AGENT ========================
cat > packages/agents/red_team/agent.py << 'PYEOF'
"""Red Team Agent — adversarial stress-testing of hypothesis trees."""
from __future__ import annotations

import json
import logging
from itertools import combinations

from packages.agents.base import BaseAgent
from packages.agents.red_team.prompts import (
    ASSUMPTION_SURFACER_PROMPT,
    CONTRADICTION_PROMPT,
    DEVILS_ADVOCATE_PROMPT,
    SENSITIVITY_PROMPT,
)
from packages.shared.types import (
    Critique,
    CritiqueSeverity,
    CritiqueType,
    HypothesisNode,
    HypothesisTree,
    StressTestReport,
    TestabilityClass,
)

logger = logging.getLogger(__name__)


class RedTeamAgent(BaseAgent):
    def get_system_prompt(self) -> str:
        return "You are an adversarial Red Team analyst for strategy consulting."

    def _format_hypotheses(self, nodes: list[HypothesisNode]) -> str:
        lines = []
        for n in nodes:
            data_summary = ""
            if n.data_card and n.data_card.data_points:
                pts = "; ".join(f"{d.metric}: {d.value}" for d in n.data_card.data_points[:3])
                data_summary = f" [Data: {pts}]"
            lines.append(f"- [{n.id}] {n.statement}{data_summary}")
        return "\n".join(lines)

    def _format_pairs(self, pairs: list[tuple[HypothesisNode, HypothesisNode]]) -> str:
        lines = []
        for a, b in pairs:
            lines.append(f"Pair:\n  A [{a.id}]: {a.statement}\n  B [{b.id}]: {b.statement}")
        return "\n\n".join(lines)

    def _parse_critiques(self, raw: str, critique_type: CritiqueType, nodes_map: dict[str, HypothesisNode]) -> list[Critique]:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            logger.warning("Failed to parse red team response")
            return []

        critiques = []
        for c in data.get("critiques", []):
            target_id = c.get("target_node_id", "")
            target_node = nodes_map.get(target_id)
            related_id = c.get("related_node_id")
            related_node = nodes_map.get(related_id, None) if related_id else None

            try:
                severity = CritiqueSeverity(c.get("severity", "note"))
            except ValueError:
                severity = CritiqueSeverity.NOTE

            critiques.append(Critique(
                critique_type=critique_type,
                severity=severity,
                target_node_id=target_id,
                target_node_statement=target_node.statement if target_node else "",
                related_node_id=related_id or "",
                related_node_statement=related_node.statement if related_node else "",
                claim_challenged=c.get("claim_challenged", ""),
                evidence_basis=c.get("evidence_basis", ""),
                suggested_resolution=c.get("suggested_resolution", ""),
                breakpoint_info=c.get("breakpoint_info"),
            ))
        return critiques

    def stress_test(self, tree: HypothesisTree) -> StressTestReport:
        logger.info("Starting stress test...")
        all_nodes = tree.get_all_nodes()
        leaves = tree.get_leaf_nodes()
        nodes_map = {n.id: n for n in all_nodes}

        all_critiques: list[Critique] = []

        # 1. Devil's Advocate — top 10 by priority
        high_impact = sorted(
            [l for l in leaves if l.testability],
            key=lambda n: n.testability.priority_score if n.testability else 0,
            reverse=True,
        )[:10]

        if high_impact:
            logger.info("Running Devil's Advocate on %d hypotheses", len(high_impact))
            prompt = DEVILS_ADVOCATE_PROMPT.format(
                industry=tree.industry, company=tree.company, question=tree.question,
                hypotheses_block=self._format_hypotheses(high_impact),
            )
            raw = self.call_llm(prompt)
            all_critiques.extend(self._parse_critiques(raw, CritiqueType.DEVILS_ADVOCATE, nodes_map))

        # 2. Assumption Surfacer — all leaves
        if leaves:
            # Process in batches of 12
            for i in range(0, len(leaves), 12):
                batch = leaves[i:i+12]
                logger.info("Running Assumption Surfacer on batch %d (%d hypotheses)", i // 12 + 1, len(batch))
                prompt = ASSUMPTION_SURFACER_PROMPT.format(
                    industry=tree.industry, company=tree.company, question=tree.question,
                    hypotheses_block=self._format_hypotheses(batch),
                )
                raw = self.call_llm(prompt)
                all_critiques.extend(self._parse_critiques(raw, CritiqueType.HIDDEN_ASSUMPTION, nodes_map))

        # 3. Sensitivity Analyzer — quantitative leaves with data
        quant_with_data = [
            l for l in leaves
            if l.testability
            and l.testability.classification == TestabilityClass.QUANTITATIVE
            and l.data_card
            and l.data_card.data_points
        ]
        if quant_with_data:
            logger.info("Running Sensitivity Analyzer on %d hypotheses", len(quant_with_data))
            prompt = SENSITIVITY_PROMPT.format(
                industry=tree.industry, company=tree.company, question=tree.question,
                hypotheses_block=self._format_hypotheses(quant_with_data),
            )
            raw = self.call_llm(prompt)
            all_critiques.extend(self._parse_critiques(raw, CritiqueType.SENSITIVITY, nodes_map))

        # 4. Contradiction Detector — pairwise on first-level branches
        first_level = [c for c in tree.root.children]
        if len(first_level) >= 2:
            # Get representative leaves from each branch
            branch_reps: list[HypothesisNode] = []
            for branch in first_level:
                branch_leaves = [n for n in self._collect_all(branch) if n.is_leaf]
                if branch_leaves:
                    # Pick highest-impact leaf from each branch
                    best = max(
                        branch_leaves,
                        key=lambda n: n.testability.priority_score if n.testability else 0,
                    )
                    branch_reps.append(best)

            if len(branch_reps) >= 2:
                pairs = list(combinations(branch_reps, 2))[:10]
                logger.info("Running Contradiction Detector on %d pairs", len(pairs))
                prompt = CONTRADICTION_PROMPT.format(
                    industry=tree.industry, company=tree.company, question=tree.question,
                    pairs_block=self._format_pairs(pairs),
                )
                raw = self.call_llm(prompt)
                all_critiques.extend(self._parse_critiques(raw, CritiqueType.CONTRADICTION, nodes_map))

        # Build report
        report = StressTestReport(critiques=all_critiques)
        report.compute_counts()

        # Tag nodes with worst severity
        severity_order = {CritiqueSeverity.CRITICAL: 3, CritiqueSeverity.WARNING: 2, CritiqueSeverity.NOTE: 1}
        for critique in all_critiques:
            node = nodes_map.get(critique.target_node_id)
            if node:
                current = severity_order.get(node.stress_test_severity, 0) if node.stress_test_severity else 0
                new = severity_order.get(critique.severity, 0)
                if new > current:
                    node.stress_test_severity = critique.severity

        report.summary = (
            f"Stress test complete: {report.critical_count} critical, "
            f"{report.warning_count} warnings, {report.note_count} notes "
            f"across {len(all_critiques)} total critiques."
        )

        logger.info(report.summary)
        return report

    @staticmethod
    def _collect_all(node: HypothesisNode) -> list[HypothesisNode]:
        result = [node]
        for child in node.children:
            result.extend(RedTeamAgent._collect_all(child))
        return result
PYEOF

# ======================== UPDATE ORCHESTRATOR — add Phase 4 ========================
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
            industry=industry, company=company, question=question,
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
                statement=child_data["statement"], parent_id=root.id,
                what_must_be_true=child_data.get("what_must_be_true"),
                evidence_needed=child_data.get("evidence_needed"), depth=1,
            )
            root.children.append(child)
        return root

    def _decompose_with_validation(self, node, industry, company, question):
        children = self.decomposer.decompose(parent=node, industry=industry, company=company, question=question)
        best_children, best_score = children, 999
        for attempt in range(MECE_MAX_RETRIES):
            validation = self.mece_validator.validate(parent=node, children=children)
            score = len(validation.overlaps) + len(validation.gaps)
            if score < best_score:
                best_score, best_children = score, children
            if validation.is_valid:
                logger.info("MECE passed on attempt %d for '%s'", attempt + 1, node.statement[:50])
                return children
            logger.info("MECE attempt %d/%d for '%s': overlaps=%d gaps=%d",
                attempt + 1, MECE_MAX_RETRIES, node.statement[:50],
                len(validation.overlaps), len(validation.gaps))
            if attempt < MECE_MAX_RETRIES - 1:
                children = self.decomposer.decompose(
                    parent=node, industry=industry, company=company,
                    question=question, previous_issues=validation)
        logger.warning("MECE exhausted for '%s'. Accepting best (score=%d).", node.statement[:50], best_score)
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
            analysis = self.analysis_designer.design(
                node=node, testability=testability, industry=industry, company=company, question=question)
            node.analysis = analysis

    def generate_tree(self, industry: str, company: str, question: str) -> HypothesisTree:
        logger.info("Starting tree generation: %s / %s / %s", industry, company, question)

        # Phase 1
        classification = self.classify_question(industry, company, question)
        logger.info("Classification: %s (%.2f)", classification.question_type, classification.confidence)
        root = self.generate_root_and_branches(industry, company, question, classification)
        logger.info("Root generated with %d first-level branches", len(root.children))
        self._decompose_recursive(root, industry, company, question, TARGET_TREE_DEPTH)
        all_nodes = self._collect_all(root)
        leaf_count = len([n for n in all_nodes if n.is_leaf])
        logger.info("Phase 1 complete: %d nodes, %d leaves", len(all_nodes), leaf_count)

        # Phase 2
        logger.info("Starting Phase 2: testability + analysis design...")
        self._classify_and_design(root, industry, company, question)
        logger.info("Phase 2 complete: %d leaves classified", len([n for n in all_nodes if n.testability]))

        # Phase 3
        logger.info("Starting Phase 3: data pre-population...")
        self.data_retrieval.retrieve_for_tree(root, industry, company, question)
        logger.info("Phase 3 complete: %d leaves with data cards", len([n for n in all_nodes if n.data_card]))

        # Build tree object for Phase 4
        tree = HypothesisTree(
            root=root, classification=classification,
            industry=industry, company=company, question=question,
        )

        # Phase 4
        logger.info("Starting Phase 4: adversarial stress-testing...")
        report = self.red_team.stress_test(tree)
        tree.stress_test_report = report
        logger.info("Phase 4 complete: %s", report.summary)

        return tree

    @staticmethod
    def _collect_all(node: HypothesisNode) -> list[HypothesisNode]:
        result = [node]
        for child in node.children:
            result.extend(OrchestratorAgent._collect_all(child))
        return result
PYEOF

# ======================== FRONTEND TYPES — add stress test types ========================
cat > apps/web/src/types/hypothesis.ts << 'TSEOF'
export type QuestionType =
  | 'growth_market_entry' | 'cost_optimization' | 'ma_rationale'
  | 'pricing_strategy' | 'competitive_response' | 'digital_transformation' | 'unknown';

export type TestabilityClass = 'quantitative' | 'qualitative' | 'assumption' | 'already_answered';

export type AnalysisType =
  | 'regression' | 'benchmarking' | 'cohort_analysis' | 'scenario_modeling'
  | 'break_even' | 'market_sizing' | 'competitive_analysis' | 'financial_modeling'
  | 'survey_analysis' | 'expert_interviews' | 'case_study' | 'data_analysis'
  | 'cost_analysis' | 'sensitivity_analysis';

export type ConfidenceLevel = 'high' | 'medium' | 'low';
export type CritiqueSeverity = 'critical' | 'warning' | 'note';
export type CritiqueType = 'devils_advocate' | 'hidden_assumption' | 'sensitivity' | 'contradiction';

export interface Critique {
  critique_type: CritiqueType;
  severity: CritiqueSeverity;
  target_node_id: string;
  target_node_statement: string;
  related_node_id: string | null;
  related_node_statement: string;
  claim_challenged: string;
  evidence_basis: string;
  suggested_resolution: string;
  breakpoint_info: string | null;
}

export interface StressTestReport {
  critiques: Critique[];
  summary: string;
  critical_count: number;
  warning_count: number;
  note_count: number;
}

export interface DataPoint {
  metric: string; value: string; source: string; source_url: string;
  confidence: ConfidenceLevel; recency: string; notes: string;
}

export interface DataGap {
  description: string; why_needed: string; suggested_alternative: string;
}

export interface DataCard {
  hypothesis_id: string; data_points: DataPoint[]; gaps: DataGap[];
  summary: string; retrieval_status: string;
}

export interface TestabilityResult {
  classification: TestabilityClass; confidence: number; rationale: string;
  impact_score: number; testability_score: number; data_availability_score: number;
  priority_score?: number;
}

export interface AnalysisDesign {
  analysis_type: AnalysisType; methodology: string; data_sources: string[];
  output_format: string; loe_hours: number; rationale: string;
}

export interface HypothesisNode {
  id: string; statement: string; parent_id: string | null; children: HypothesisNode[];
  depth: number; what_must_be_true: string | null; evidence_needed: string | null;
  is_leaf: boolean; testability: TestabilityResult | null; analysis: AnalysisDesign | null;
  data_card: DataCard | null; stress_test_severity: CritiqueSeverity | null;
}

export interface ClassificationResult {
  question_type: QuestionType; framework: string; confidence: number; rationale: string;
}

export interface HypothesisTree {
  id: string; root: HypothesisNode; classification: ClassificationResult;
  industry: string; company: string; question: string; created_at: string;
  metadata: Record<string, unknown>; stress_test_report: StressTestReport | null;
}
TSEOF

# ======================== STRESS TEST REPORT COMPONENT ========================
mkdir -p apps/web/src/components/stress-test

cat > apps/web/src/components/stress-test/StressTestReport.tsx << 'TSEOF'
import { useState } from 'react';
import type { StressTestReport as Report, Critique, CritiqueSeverity, CritiqueType } from '@/types/hypothesis';

const SEVERITY_STYLES: Record<CritiqueSeverity, { bg: string; border: string; text: string; icon: string }> = {
  critical: { bg: 'bg-red-50', border: 'border-red-200', text: 'text-red-700', icon: '\u2716' },
  warning: { bg: 'bg-amber-50', border: 'border-amber-200', text: 'text-amber-700', icon: '\u26A0' },
  note: { bg: 'bg-blue-50', border: 'border-blue-200', text: 'text-blue-700', icon: '\u2139' },
};

const TYPE_LABELS: Record<CritiqueType, string> = {
  devils_advocate: "Devil's Advocate",
  hidden_assumption: 'Hidden Assumption',
  sensitivity: 'Sensitivity',
  contradiction: 'Contradiction',
};

function CritiqueCard({ critique }: { critique: Critique }) {
  const style = SEVERITY_STYLES[critique.severity];
  return (
    <div className={`border rounded-lg p-4 ${style.bg} ${style.border}`}>
      <div className="flex items-start gap-2">
        <span className={`text-lg ${style.text}`}>{style.icon}</span>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1 flex-wrap">
            <span className={`text-xs font-semibold uppercase ${style.text}`}>{critique.severity}</span>
            <span className="text-xs bg-white bg-opacity-60 text-slate-600 px-1.5 py-0.5 rounded">
              {TYPE_LABELS[critique.critique_type]}
            </span>
          </div>
          <p className="text-sm font-medium text-slate-800 mb-1">{critique.claim_challenged}</p>
          <p className="text-sm text-slate-600 mb-2">{critique.evidence_basis}</p>
          {critique.breakpoint_info && (
            <p className="text-sm text-slate-700 bg-white bg-opacity-50 p-2 rounded mb-2 font-mono text-xs">
              {critique.breakpoint_info}
            </p>
          )}
          {critique.suggested_resolution && (
            <p className="text-xs text-slate-500 italic">Resolution: {critique.suggested_resolution}</p>
          )}
          <div className="mt-2 text-xs text-slate-400">
            Target: {critique.target_node_statement.substring(0, 80)}...
            {critique.related_node_statement && (
              <span className="block mt-0.5">Related: {critique.related_node_statement.substring(0, 80)}...</span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

interface Props {
  report: Report;
}

export function StressTestReportView({ report }: Props) {
  const [filterSeverity, setFilterSeverity] = useState<CritiqueSeverity | 'all'>('all');
  const [filterType, setFilterType] = useState<CritiqueType | 'all'>('all');

  const filtered = report.critiques.filter((c) => {
    if (filterSeverity !== 'all' && c.severity !== filterSeverity) return false;
    if (filterType !== 'all' && c.critique_type !== filterType) return false;
    return true;
  });

  // Sort: critical first, then warning, then note
  const severityOrder: Record<CritiqueSeverity, number> = { critical: 0, warning: 1, note: 2 };
  filtered.sort((a, b) => severityOrder[a.severity] - severityOrder[b.severity]);

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold text-slate-800">Stress Test Report</h3>
          <p className="text-sm text-slate-500 mt-1">{report.summary}</p>
        </div>
        <div className="flex gap-3">
          <div className="flex gap-1.5">
            <span className="inline-flex items-center gap-1 text-xs bg-red-100 text-red-700 px-2 py-1 rounded-full font-medium">
              {report.critical_count} Critical
            </span>
            <span className="inline-flex items-center gap-1 text-xs bg-amber-100 text-amber-700 px-2 py-1 rounded-full font-medium">
              {report.warning_count} Warning
            </span>
            <span className="inline-flex items-center gap-1 text-xs bg-blue-100 text-blue-700 px-2 py-1 rounded-full font-medium">
              {report.note_count} Note
            </span>
          </div>
        </div>
      </div>

      <div className="flex gap-2 mb-4">
        <select
          value={filterSeverity}
          onChange={(e) => setFilterSeverity(e.target.value as CritiqueSeverity | 'all')}
          className="text-sm border border-slate-300 rounded-lg px-2 py-1"
        >
          <option value="all">All Severities</option>
          <option value="critical">Critical</option>
          <option value="warning">Warning</option>
          <option value="note">Note</option>
        </select>
        <select
          value={filterType}
          onChange={(e) => setFilterType(e.target.value as CritiqueType | 'all')}
          className="text-sm border border-slate-300 rounded-lg px-2 py-1"
        >
          <option value="all">All Types</option>
          <option value="devils_advocate">Devil's Advocate</option>
          <option value="hidden_assumption">Hidden Assumptions</option>
          <option value="sensitivity">Sensitivity</option>
          <option value="contradiction">Contradictions</option>
        </select>
      </div>

      <div className="space-y-3">
        {filtered.map((critique, i) => (
          <CritiqueCard key={i} critique={critique} />
        ))}
        {filtered.length === 0 && (
          <p className="text-sm text-slate-400 text-center py-8">No critiques match the current filters.</p>
        )}
      </div>
    </div>
  );
}
TSEOF

# ======================== UPDATED TREE VIEW — stress severity badges ========================
cat > apps/web/src/components/tree/HypothesisTree.tsx << 'TSEOF'
import { useState } from 'react';
import type { HypothesisNode as HNode } from '@/types/hypothesis';
import { NodeDetailPanel } from './NodeDetailPanel';
import { TestabilityBadge } from '@/components/analysis/TestabilityBadge';
import { depthColor, cn } from '@/lib/utils';

const SEVERITY_DOT: Record<string, string> = {
  critical: 'bg-red-500',
  warning: 'bg-amber-400',
  note: 'bg-blue-400',
};

interface TreeNodeProps {
  node: HNode;
  onSelect: (node: HNode) => void;
  selectedId: string | null;
}

function TreeNode({ node, onSelect, selectedId }: TreeNodeProps) {
  const [collapsed, setCollapsed] = useState(false);
  const hasChildren = node.children.length > 0;
  const isSelected = node.id === selectedId;
  const hasData = node.data_card && node.data_card.data_points.length > 0;
  const hasGaps = node.data_card && node.data_card.gaps.length > 0;

  return (
    <div className="ml-4 first:ml-0">
      <div
        className={cn(
          'flex items-start gap-2 p-3 rounded-lg mb-1 cursor-pointer transition-all border',
          isSelected ? 'border-blue-400 bg-blue-50 shadow-sm' : 'border-transparent hover:bg-slate-50',
          node.stress_test_severity === 'critical' && !isSelected && 'border-red-200 bg-red-50/30',
        )}
        onClick={() => onSelect(node)}
      >
        {hasChildren && (
          <button
            onClick={(e) => { e.stopPropagation(); setCollapsed(!collapsed); }}
            className="mt-0.5 text-slate-400 hover:text-slate-600 text-sm flex-shrink-0 w-5 text-center"
          >
            {collapsed ? '\u25B8' : '\u25BE'}
          </button>
        )}
        {!hasChildren && <div className="w-5 flex-shrink-0" />}
        <div className={`w-2 h-2 rounded-full mt-1.5 flex-shrink-0 ${depthColor(node.depth)}`} />
        <div className="min-w-0 flex-1">
          <p className="text-sm text-slate-800 leading-snug">{node.statement}</p>
          <div className="flex gap-2 mt-1 items-center flex-wrap">
            <span className="text-xs text-slate-400 font-mono">d{node.depth}</span>
            {node.is_leaf && <span className="text-xs bg-emerald-100 text-emerald-700 px-1.5 rounded">leaf</span>}
            {node.testability && <TestabilityBadge classification={node.testability.classification} />}
            {node.analysis && (
              <span className="text-xs bg-slate-100 text-slate-500 px-1.5 rounded">
                {node.analysis.analysis_type.replace(/_/g, ' ')}
              </span>
            )}
            {hasData && (
              <span className="text-xs bg-blue-100 text-blue-600 px-1.5 rounded">
                {node.data_card!.data_points.length} data pts
              </span>
            )}
            {hasGaps && !hasData && (
              <span className="text-xs bg-amber-100 text-amber-600 px-1.5 rounded">
                {node.data_card!.gaps.length} gaps
              </span>
            )}
            {node.stress_test_severity && (
              <span className="flex items-center gap-1 text-xs">
                <span className={`w-2 h-2 rounded-full ${SEVERITY_DOT[node.stress_test_severity]}`} />
                <span className="text-slate-400">{node.stress_test_severity}</span>
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

# ======================== UPDATED APP — add stress test tab ========================
cat > apps/web/src/App.tsx << 'TSEOF'
import { useState } from 'react';
import { QuestionInput } from '@/components/forms/QuestionInput';
import { HypothesisTreeView } from '@/components/tree/HypothesisTree';
import { AnalysisPlanTable } from '@/components/analysis/AnalysisPlanTable';
import { StressTestReportView } from '@/components/stress-test/StressTestReport';
import { LoadingState } from '@/components/common/LoadingState';
import { ErrorBoundary } from '@/components/common/ErrorBoundary';
import { api } from '@/lib/api';
import type { Project, ProjectCreate } from '@/types/project';

type ViewMode = 'tree' | 'table' | 'stress';

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

  const tabs: { key: ViewMode; label: string; show: boolean }[] = [
    { key: 'tree', label: 'Tree View', show: true },
    { key: 'table', label: 'Analysis Plan', show: true },
    { key: 'stress', label: 'Stress Test', show: !!project?.tree?.stress_test_report },
  ];

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
                  {tabs.filter((t) => t.show).map((tab) => (
                    <button
                      key={tab.key}
                      onClick={() => setViewMode(tab.key)}
                      className={`px-3 py-1 text-sm rounded-md transition-colors ${
                        viewMode === tab.key
                          ? 'bg-white text-slate-800 shadow-sm'
                          : 'text-slate-500 hover:text-slate-700'
                      }`}
                    >
                      {tab.label}
                      {tab.key === 'stress' && project?.tree?.stress_test_report && (
                        <span className="ml-1.5 inline-flex items-center justify-center w-5 h-5 text-xs bg-red-100 text-red-600 rounded-full">
                          {project.tree.stress_test_report.critical_count}
                        </span>
                      )}
                    </button>
                  ))}
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
            <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">{error}</div>
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
              {viewMode === 'stress' && project.tree.stress_test_report && (
                <StressTestReportView report={project.tree.stress_test_report} />
              )}
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
  'Generating hypothesis tree...',
  'Validating MECE structure...',
  'Classifying testability...',
  'Designing analyses...',
  'Fetching financial data...',
  'Matching data to hypotheses...',
  'Running Devil\'s Advocate...',
  'Surfacing hidden assumptions...',
  'Analyzing sensitivity...',
  'Detecting contradictions...',
  'Compiling stress test report...',
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
      <p className="text-xs text-slate-400 mt-6">Full pipeline typically takes 6-10 minutes</p>
    </div>
  );
}
TSEOF

echo ""
echo "=== Phase 4 files written ==="
echo ""
echo "New features:"
echo "  - Red Team Agent with 4 sub-capabilities:"
echo "    1. Devil's Advocate: strongest counterarguments for top-10 priority hypotheses"
echo "    2. Assumption Surfacer: hidden assumptions across all leaves (batched)"
echo "    3. Sensitivity Analyzer: breakpoints for quantitative hypotheses with data"
echo "    4. Contradiction Detector: cross-branch conflict detection"
echo "  - Each critique has: severity (critical/warning/note), claim challenged,"
echo "    evidence basis, suggested resolution, and optional breakpoint info"
echo "  - Tree nodes tagged with worst severity (red/amber/blue dots)"
echo "  - Critical nodes get red background tint in tree view"
echo "  - New 'Stress Test' tab with filterable report view"
echo "  - Stress Test tab shows critical count badge"
echo ""
echo "Restart backend, generate a new tree. Check the Stress Test tab."