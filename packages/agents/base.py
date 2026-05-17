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
