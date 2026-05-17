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
