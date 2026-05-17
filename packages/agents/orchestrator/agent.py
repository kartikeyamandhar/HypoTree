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
