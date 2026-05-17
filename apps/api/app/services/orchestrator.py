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
