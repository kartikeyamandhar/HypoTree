"""Project endpoints with SSE log streaming."""
from __future__ import annotations

import asyncio
import json
import logging
import uuid
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

from packages.agents.orchestrator.agent import OrchestratorAgent
from packages.shared.types import ProjectCreate, ProjectResponse
from app.services.orchestrator import get_or_create_queue, get_logs, clear_logs

logger = logging.getLogger(__name__)
router = APIRouter(tags=["projects"])

_projects: dict[str, dict] = {}
_executor = ThreadPoolExecutor(max_workers=2)


@router.post("/projects", response_model=ProjectResponse)
async def create_project(body: ProjectCreate):
    project_id = str(uuid.uuid4())
    project = {"id": project_id, "industry": body.industry, "company": body.company,
        "question": body.question, "status": "created", "tree": None, "created_at": datetime.utcnow()}
    _projects[project_id] = project
    return ProjectResponse(**project)


def _run_generation(project_id: str, industry: str, company: str, question: str):
    """Run in thread pool to not block the event loop."""
    try:
        tree = OrchestratorAgent().generate_tree(industry, company, question, project_id=project_id)
        _projects[project_id]["tree"] = tree
        _projects[project_id]["status"] = "complete"
    except Exception as e:
        logger.exception("Generation failed")
        _projects[project_id]["status"] = "error"
        _projects[project_id]["error"] = str(e)


@router.post("/projects/{project_id}/generate", response_model=ProjectResponse)
async def generate_tree(project_id: str):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404, "Project not found")
    if project["tree"]: raise HTTPException(400, "Already generated")
    project["status"] = "generating"

    # Run in background thread
    loop = asyncio.get_event_loop()
    loop.run_in_executor(_executor, _run_generation, project_id, project["industry"], project["company"], project["question"])

    # Return immediately so frontend can start polling SSE
    return ProjectResponse(**project)


@router.get("/projects/{project_id}/stream")
async def stream_logs(project_id: str):
    """SSE endpoint streaming real-time agent logs."""
    queue = get_or_create_queue(project_id)

    async def event_generator():
        # First send any logs already accumulated
        for entry in get_logs(project_id):
            yield f"data: {json.dumps(entry)}\n\n"

        # Then stream new ones
        while True:
            try:
                entry = await asyncio.wait_for(queue.get(), timeout=1.0)
                yield f"data: {json.dumps(entry)}\n\n"
                if entry.get("phase") == "done":
                    break
            except asyncio.TimeoutError:
                yield f": keepalive\n\n"
                # Check if project is done
                project = _projects.get(project_id)
                if project and project["status"] in ("complete", "error"):
                    yield f"data: {json.dumps({'phase': 'done', 'agent': 'System', 'message': project['status'], 'level': 'info'})}\n\n"
                    break

    return StreamingResponse(event_generator(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive", "X-Accel-Buffering": "no"})


@router.get("/projects/{project_id}", response_model=ProjectResponse)
async def get_project(project_id: str):
    project = _projects.get(project_id)
    if not project: raise HTTPException(404)
    return ProjectResponse(**project)


@router.get("/projects", response_model=list[ProjectResponse])
async def list_projects():
    return [ProjectResponse(**p) for p in _projects.values()]
