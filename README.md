# HypoTree
 
**Structured Strategy Decomposition Engine**
 
HypoTree compresses the structural scaffolding of strategy consulting case work. It does not produce strategic insight. It automates the repeatable decomposition, classification, data retrieval, and workplan construction that a case team builds before the actual analytical thinking begins.
 
Given an industry, company, and strategic question, it produces a MECE hypothesis tree, classifies testability, designs analyses, retrieves public financial data, stress-tests assumptions, maps causal dependencies, and generates a sequenced workplan.
 
## What It Does
 
Ten specialized agents run in sequence, each handling one piece of early-stage case structuring:
 
**Orchestrator** classifies the question type (M&A rationale, market entry, cost optimization, pricing strategy, competitive response, digital transformation) and selects a decomposition framework. Synergy tree for M&A. 3Cs plus market attractiveness for market entry. Value chain decomposition for cost optimization. The framework selection is reasoned, not templated.
 
**Decomposer** breaks each hypothesis into sub-hypotheses recursively, three to four levels deep.
 
**MECE Validator** performs heuristic semantic overlap detection on every sibling set. It catches obvious duplications and coverage gaps. It does not formally verify conceptual independence or causal separability. Those require human judgment. After a configurable number of retry attempts, it accepts the best available decomposition rather than blocking the pipeline. This is a practical design choice, not a claim that MECE validation is solved.
 
**Testability Classifier** scores every leaf on impact (1-5), testability (1-3), and data availability (1-3). The product becomes a prioritized backlog. Classification is systematic but should be reviewed by the team.
 
**Analysis Designer** proposes methodology per hypothesis: benchmarking, scenario modeling, regression, cohort analysis, etc., with suggested data sources. LOE estimates are rough heuristics from the LLM, not calibrated against real project data. Treat them as starting points, not commitments.
 
**Data Retrieval Agent** pulls real financials from Yahoo Finance and SEC EDGAR. Revenue, margins, market cap, multiples, filing dates. Each data point attached to the relevant hypothesis with source-quality-based confidence scoring (SEC filings rate higher than secondary sources). Gaps flagged explicitly.
 
**Red Team Agent** attacks the completed tree through four modes:
- Devil's Advocate: evidence-grounded counterarguments for high-priority hypotheses
- Assumption Surfacer: identifies unstated assumptions and rates fragility
- Sensitivity Analyzer: finds quantitative breakpoints where conclusions flip
- Contradiction Detector: scans for conflicting assumptions across branches
 
**DAG Builder** identifies causal dependencies between hypotheses and constructs a directed graph. The propagation is heuristic (product of source probabilities times edge strength), not a proper Bayesian network with learned parameters. Appropriate for interactive scenario exploration. Not a substitute for formal causal inference.
 
**Workplan Compiler** groups hypotheses into workstreams by methodology and data source affinity, sequences by dependency, assigns resource type (analyst/manager/partner). Modifiable via natural language negotiation.
 
**Memory Store** saves completed analyses to SQLite. Retrieves structurally similar past cases when new questions arrive. Quality improves with accumulated feedback.
 
## Where It Is Strong
 
- Early-stage strategy structuring
- Investment memo scaffolding
- PE/VC diligence framing
- Market entry analysis setup
- M&A synergy decomposition
- Internal corporate strategy triage
- Any context where the frameworks are known and the initial data is public
 
## Where It Is Not Strong
 
- Operational transformation requiring proprietary client data
- Implementation-heavy consulting (org redesign, change management)
- Situations bottlenecked by interviews, internal metrics, ERP exports, or political dynamics
- Any question where the answer depends on information that is not publicly available
 
## Honest Limitations
 
**Decomposition quality is the binding constraint.** Everything downstream depends on the initial tree. If the first decomposition frames the problem incorrectly, the entire pipeline optimizes in the wrong direction. The MECE validator catches structural issues but cannot evaluate whether the decomposition is strategically useful. That judgment remains human.
 
**MECE validation is heuristic, not formal.** The validator detects semantic overlap and obvious gaps. It does not verify conceptual independence, causal separability, or whether the abstraction level is appropriate. Real MECE debates in consulting involve judgment calls that this system cannot make.
 
**LOE estimates are not calibrated.** The analysis designer outputs hour estimates based on LLM pattern matching, not grounded project data. These should be treated as rough ranges, not commitments. Calibration requires a feedback loop from actual project outcomes that does not yet exist.
 
**Public data has a ceiling.** The system retrieves from Yahoo Finance and SEC EDGAR. It does not access proprietary databases, client data, or gated research. For many consulting questions, the critical data is internal.
 
**The dependency graph is simplified.** Probability propagation uses heuristic AND-logic on edge weights, not Bayesian inference with learned parameters. It is useful for interactive "what-if" exploration but should not be mistaken for rigorous causal modeling.
 
**Workflow insertion is unsolved.** The technical architecture works. The organizational question of where this fits in a consulting workflow, who trusts the output, when humans override, and whether a partner can defend AI-generated structure to a client is a harder problem that this project does not address.
 
## Architecture
 
```
apps/
  web/          React + TypeScript + Vite
  api/          FastAPI + Python
 
packages/
  agents/       10 specialized agents
    orchestrator/       Question classification, framework selection, pipeline sequencing
    decomposer/         Recursive sub-hypothesis generation
    mece_validator/     Heuristic overlap and gap detection
    testability_classifier/  Impact, testability, data availability scoring
    analysis_designer/  Methodology proposal with data sources
    data_retrieval/     Yahoo Finance + SEC EDGAR integration
    red_team/           4-mode adversarial stress-testing
    graph/              Causal dependency mapping + heuristic propagation
    workplan/           Workstream compilation + NL negotiation
    memory/             SQLite episodic memory
    evaluation/         Feedback collection + calibration tracking
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
| LLM | Anthropic Claude (Sonnet) |
| Data Sources | Yahoo Finance, SEC EDGAR (free, no keys needed) |
| Memory | SQLite (zero config) |
| Real-time | Server-Sent Events for live agent feed |
| Export | python-pptx for PowerPoint generation |
 
## Quick Start
 
```bash
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
2. Watch the live agent feed as the pipeline processes
3. Explore five views:
   - **Hypothesis Tree** with testability classification and data indicators
   - **Analysis Plan** sorted by priority with methodology and LOE
   - **Red Team Report** with severity-ranked critiques filterable by type
   - **Scenarios** with TRUE/FALSE toggles and probability cascade
   - **Workplan** with workstream sequencing and NL negotiation
4. Export to PowerPoint
5. Leave post-case feedback on leaf nodes
6. Run subsequent questions to see episodic memory in action
 
## Example Questions
 
```
Semiconductor / Skyworks / Should Skyworks and Qorvo merge?
Retail / Nike / Should Nike acquire Allbirds?
Online Travel / Expedia / Should Expedia acquire Booking Holdings?
Ride-hailing / Grab / Should Grab expand into EV logistics in Vietnam?
```