from __future__ import annotations
from pydantic import BaseModel, Field


class WorkItem(BaseModel):
    hypothesis_id: str
    hypothesis_statement: str = ""
    analysis_type: str = ""
    loe_hours: float = 0.0
    resource_type: str = "analyst"  # analyst, manager, partner


class Workstream(BaseModel):
    id: str
    name: str
    description: str = ""
    items: list[WorkItem] = Field(default_factory=list)
    total_loe: float = 0.0
    sequence_order: int = 0
    depends_on: list[str] = Field(default_factory=list)


class Workplan(BaseModel):
    workstreams: list[Workstream] = Field(default_factory=list)
    total_loe: float = 0.0
    estimated_weeks: float = 0.0
    critical_path: list[str] = Field(default_factory=list)
    summary: str = ""
