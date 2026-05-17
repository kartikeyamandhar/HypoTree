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
