"""Evaluation and calibration tracking."""
from __future__ import annotations

import logging
import sqlite3
import os
from collections import defaultdict
from typing import Optional

logger = logging.getLogger(__name__)

DB_PATH = os.environ.get("HYPOTREE_MEMORY_DB", os.path.join(os.path.dirname(__file__), "..", "..", "..", "hypotree_memory.db"))


def _conn():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""CREATE TABLE IF NOT EXISTS evaluations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        case_id TEXT,
        question_type TEXT,
        total_nodes INTEGER,
        total_leaves INTEGER,
        feedback_correct INTEGER DEFAULT 0,
        feedback_incorrect INTEGER DEFAULT 0,
        feedback_irrelevant INTEGER DEFAULT 0,
        feedback_missing INTEGER DEFAULT 0,
        confidence_avg REAL DEFAULT 0,
        created_at TEXT
    )""")
    conn.commit()
    return conn


def record_evaluation(case_id: str, question_type: str, total_nodes: int, total_leaves: int,
                      correct: int, incorrect: int, irrelevant: int, missing: int, confidence_avg: float):
    from datetime import datetime
    c = _conn()
    c.execute(
        """INSERT INTO evaluations (case_id, question_type, total_nodes, total_leaves,
           feedback_correct, feedback_incorrect, feedback_irrelevant, feedback_missing,
           confidence_avg, created_at) VALUES (?,?,?,?,?,?,?,?,?,?)""",
        (case_id, question_type, total_nodes, total_leaves, correct, incorrect, irrelevant, missing,
         confidence_avg, datetime.utcnow().isoformat())
    )
    c.commit()
    c.close()


def get_calibration_data() -> dict:
    """Compute calibration metrics from all feedback."""
    c = _conn()
    cursor = c.execute("SELECT question_type, feedback_correct, feedback_incorrect, feedback_irrelevant, feedback_missing, confidence_avg FROM evaluations")

    by_type: dict[str, dict] = defaultdict(lambda: {"correct": 0, "incorrect": 0, "irrelevant": 0, "missing": 0, "count": 0, "confidence_sum": 0})
    totals = {"correct": 0, "incorrect": 0, "irrelevant": 0, "missing": 0, "count": 0}

    for row in cursor.fetchall():
        qt = row[0]
        by_type[qt]["correct"] += row[1]
        by_type[qt]["incorrect"] += row[2]
        by_type[qt]["irrelevant"] += row[3]
        by_type[qt]["missing"] += row[4]
        by_type[qt]["confidence_sum"] += row[5]
        by_type[qt]["count"] += 1
        totals["correct"] += row[1]
        totals["incorrect"] += row[2]
        totals["irrelevant"] += row[3]
        totals["missing"] += row[4]
        totals["count"] += 1

    c.close()

    total_judged = totals["correct"] + totals["incorrect"]
    precision = totals["correct"] / total_judged if total_judged > 0 else None

    by_type_summary = {}
    for qt, vals in by_type.items():
        judged = vals["correct"] + vals["incorrect"]
        by_type_summary[qt] = {
            "precision": vals["correct"] / judged if judged > 0 else None,
            "total_feedback": vals["correct"] + vals["incorrect"] + vals["irrelevant"] + vals["missing"],
            "avg_confidence": vals["confidence_sum"] / vals["count"] if vals["count"] > 0 else None,
            "case_count": vals["count"],
        }

    return {
        "overall_precision": precision,
        "total_cases": totals["count"],
        "total_feedback_items": totals["correct"] + totals["incorrect"] + totals["irrelevant"] + totals["missing"],
        "by_question_type": by_type_summary,
    }


def get_agent_performance() -> dict:
    """Summarize agent performance from memory db."""
    c = _conn()
    cursor = c.execute("SELECT COUNT(*), AVG(total_nodes), AVG(total_leaves) FROM evaluations")
    row = cursor.fetchone()
    c.close()

    return {
        "total_evaluations": row[0] or 0,
        "avg_nodes_per_tree": round(row[1] or 0, 1),
        "avg_leaves_per_tree": round(row[2] or 0, 1),
    }
