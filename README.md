# HypoTree

Agentic Strategy Decomposition Engine.

Given an industry, company, and strategic question, produces a MECE hypothesis tree,
testability classification, analysis design, pre-populated data, and structured workplan.

## Quick Start

```bash
cp .env.example .env  # fill in ANTHROPIC_API_KEY
docker compose -f infra/docker/docker-compose.dev.yml up -d
cd apps/api && source .venv/bin/activate && uvicorn app.main:app --reload --port 8000
cd apps/web && npm run dev
```
