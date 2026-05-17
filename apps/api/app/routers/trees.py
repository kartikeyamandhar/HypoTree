"""Tree, DAG, workplan, memory, export, and evaluation endpoints."""
from __future__ import annotations

import json
import logging
import os
import uuid

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from packages.agents.graph.state import propagate_states
from packages.agents.workplan.agent import WorkplanAgent
from packages.agents.workplan.schemas import Workplan
from packages.agents.memory.store import list_all_cases, get_case_feedback, save_feedback
from packages.agents.evaluation.tracker import get_calibration_data, get_agent_performance, record_evaluation
from packages.agents.export.pptx_export import export_to_pptx
from packages.shared.types import HypothesisState

logger = logging.getLogger(__name__)
router = APIRouter(tags=["trees"])

from app.routers.projects import _projects

EXPORT_DIR = "/tmp/hypotree_exports"
os.makedirs(EXPORT_DIR, exist_ok=True)


class ToggleRequest(BaseModel):
    node_id: str
    state: HypothesisState

class NegotiateRequest(BaseModel):
    message: str

class FeedbackRequest(BaseModel):
    node_id: str
    outcome: str
    notes: str = ""

class EvaluationSubmit(BaseModel):
    correct: int = 0
    incorrect: int = 0
    irrelevant: int = 0
    missing: int = 0


@router.post("/projects/{project_id}/dag/toggle")
async def toggle_node(project_id: str, body: ToggleRequest):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    tree = project.get("tree")
    if not tree or not tree.causal_dag: raise HTTPException(400, "No DAG")
    dag = propagate_states(tree.causal_dag, body.node_id, body.state)
    tree.causal_dag = dag
    return {"node_states": {k: v.value for k, v in dag.node_states.items()}, "node_probabilities": dag.node_probabilities}


@router.post("/projects/{project_id}/workplan/negotiate")
async def negotiate_workplan(project_id: str, body: NegotiateRequest):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    tree = project.get("tree")
    if not tree or not tree.workplan: raise HTTPException(400)
    updated = WorkplanAgent().negotiate(Workplan(**tree.workplan), body.message)
    tree.workplan = updated.model_dump()
    return updated.model_dump()


@router.post("/projects/{project_id}/feedback")
async def submit_feedback(project_id: str, body: FeedbackRequest):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    tree = project.get("tree")
    if not tree: raise HTTPException(400)
    save_feedback(tree.id, body.node_id, body.outcome, body.notes)
    return {"status": "saved"}


@router.get("/projects/{project_id}/feedback")
async def get_project_feedback(project_id: str):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    tree = project.get("tree")
    if not tree: return []
    return get_case_feedback(tree.id)


@router.post("/projects/{project_id}/evaluate")
async def submit_evaluation(project_id: str, body: EvaluationSubmit):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    tree = project.get("tree")
    if not tree: raise HTTPException(400)
    all_nodes = tree.get_all_nodes()
    leaves = tree.get_leaf_nodes()
    avg_conf = tree.classification.confidence
    record_evaluation(tree.id, tree.classification.question_type.value,
        len(all_nodes), len(leaves), body.correct, body.incorrect, body.irrelevant, body.missing, avg_conf)
    return {"status": "recorded"}


@router.get("/projects/{project_id}/export/pptx")
async def export_pptx(project_id: str):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    tree = project.get("tree")
    if not tree: raise HTTPException(400, "No tree")
    filename = f"hypotree_{project_id[:8]}.pptx"
    path = os.path.join(EXPORT_DIR, filename)
    tree_dict = tree.model_dump()
    export_to_pptx(tree_dict, path)
    return FileResponse(path, filename=filename, media_type="application/vnd.openxmlformats-officedocument.presentationml.presentation")


@router.get("/evaluation/calibration")
async def calibration():
    return get_calibration_data()


@router.get("/evaluation/performance")
async def performance():
    return get_agent_performance()


@router.get("/memory/cases")
async def list_cases():
    return list_all_cases()
