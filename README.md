# HypoTree

**Agentic Strategy Decomposition Engine**

HypoTree is a multi-agent AI system that automates the first 48 hours of strategy consulting case work. Given an industry, company, and strategic question, it produces a MECE hypothesis tree, classifies testability, designs analyses, retrieves real financial data, stress-tests assumptions, models scenarios, and generates a structured workplan.

## What It Does

Enter a strategic question like *"Should Skyworks and Qorvo merge?"* and HypoTree runs a pipeline of 10 specialized AI agents:

1. **Hypothesis Decomposition** -- Builds a 3-4 level MECE tree with recursive validation
2. **Testability Classification** -- Tags every leaf as quantitative, qualitative, assumption, or already answered with priority scoring (Impact x Testability x Data Availability)
3. **Analysis Design** -- Proposes specific methodology per hypothesis (regression, benchmarking, scenario modeling, etc.) with data sources and LOE estimates
4. **Data Pre-Population** -- Pulls real financials from Yahoo Finance and SEC EDGAR, attaches to hypotheses with confidence scoring, flags gaps explicitly
5. **Adversarial Stress-Testing** -- Red Team agent runs Devil's Advocate, Assumption Surfacer, Sensitivity Analyzer, and Contradiction Detector
6. **Causal DAG** -- Identifies dependencies between hypotheses, enables interactive scenario toggling with belief propagation
7. **Workplan Synthesis** -- Groups hypotheses into sequenced workstreams with resource allocation (analyst/manager/partner) and timeline
8. **Natural Language Negotiation** -- Modify the workplan conversationally: "We only have 3 weeks, reprioritize"
9. **Episodic Memory** -- Stores completed analyses in SQLite, retrieves similar past cases for future questions
10. **PowerPoint Export** -- Downloads a slide-ready deck with tree overview, red team findings, and workplan

## Architecture

```
apps/
  web/          React + TypeScript + Vite
  api/          FastAPI + Python

packages/
  agents/       10 specialized agents
    orchestrator/       Routes tasks, sequences phases
    decomposer/         Generates sub-hypotheses
    mece_validator/     MECE checking
    testability_classifier/  Tags leaf testability + priority
    analysis_designer/  Proposes methodology per hypothesis
    data_retrieval/     Yahoo Finance, SEC EDGAR integration
    red_team/           4-mode adversarial stress-testing
    graph/              Causal DAG builder + belief propagation
    workplan/           Workstream compiler + NL negotiation
    memory/             SQLite episodic memory store
    evaluation/         Calibration + precision tracking
    export/             PowerPoint generation
    benchmark/          Comparable case retrieval

  data-retrieval/     External API integrations
  shared/             Pydantic models, constants, utilities
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React 18, TypeScript, Vite, Tailwind CSS |
| Backend | FastAPI, Python 3.12+, Pydantic v2 |
| LLM | Anthropic Claude (Sonnet) via direct API |
| Data Sources | Yahoo Finance, SEC EDGAR (free, no keys needed) |
| Memory | SQLite (zero config) |
| Real-time | Server-Sent Events for live agent feed |
| Export | python-pptx for PowerPoint generation |

## Quick Start

```bash
# Clone
git clone https://github.com/kartikeyamandhar/HypoTree.git
cd HypoTree

# Backend
cd apps/api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Add your ANTHROPIC_API_KEY to .env
uvicorn app.main:app --reload --port 8000

# Frontend (separate terminal)
cd apps/web
npm install
npm run dev

# Open http://localhost:5173
```

Requires an Anthropic API key. No other keys, databases, or infrastructure needed.

## Usage

1. Enter industry, company, and strategic question
2. Watch the live agent feed as the pipeline processes (~8-10 min)
3. Explore 5 views:
   - **Tree** -- Expandable hypothesis tree with testability badges, data points, stress-test indicators
   - **Analysis** -- Sortable table of all hypotheses with proposed methodology and LOE
   - **Red Team** -- Severity-ranked critique report filterable by type
   - **Scenarios** -- Set hypotheses to TRUE or FALSE, watch probabilities cascade through dependencies
   - **Workplan** -- Sequenced workstreams with resource allocation and NL negotiation
4. Export to PowerPoint
5. Leave feedback on leaf nodes after the engagement concludes
6. Run another question and see past cases referenced

## Example Questions

```
Semiconductor / Skyworks / Should Skyworks and Qorvo merge?
Retail / Nike / Should Nike acquire Allbirds?
Online Travel / Expedia / Should Expedia acquire Booking Holdings?
Ride-hailing / Grab / Should Grab expand into EV logistics in Vietnam?
```

## License

MIT
