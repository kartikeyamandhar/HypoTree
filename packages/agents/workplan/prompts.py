WORKPLAN_PROMPT = """You are a strategy consulting manager building a workplan from a hypothesis tree analysis.

Context:
- Industry: {industry}
- Company: {company}
- Question: {question}

The following hypotheses have been classified and assigned analyses. Group them into 3-6 logical workstreams. Each workstream should cluster hypotheses that share data sources, methodologies, or domain affinity.

Hypotheses:
{hypotheses_block}

For each workstream, specify:
- name: short descriptive name (e.g., "Revenue Synergy Validation", "Cost Structure Analysis")
- description: one sentence scope
- sequence_order: 1 = can start immediately, 2 = needs workstream 1 results, etc.
- depends_on: list of workstream IDs this depends on (empty if none)

For each hypothesis in a workstream, assign resource_type:
- "analyst": data gathering, modeling, quantitative analysis
- "manager": synthesis, stakeholder interviews, qualitative judgment
- "partner": strategic decisions, client alignment, high-stakes assumptions

Respond ONLY with valid JSON, no markdown fences:
{{
  "workstreams": [
    {{
      "id": "ws1",
      "name": "<name>",
      "description": "<scope>",
      "sequence_order": 1,
      "depends_on": [],
      "items": [
        {{
          "hypothesis_id": "<id>",
          "resource_type": "<analyst|manager|partner>"
        }}
      ]
    }}
  ],
  "estimated_weeks": <number>,
  "summary": "<2-3 sentence workplan summary>"
}}"""

NEGOTIATION_PROMPT = """You are a strategy consulting workplan manager handling a modification request.

Current workplan:
{workplan_json}

User request: "{user_request}"

Interpret the request and produce a modified workplan. Common requests:
- Time compression: reduce weeks, drop low-priority items
- Scope changes: add/remove workstreams or hypotheses
- Resource reallocation: shift work between analyst/manager/partner
- Priority changes: reorder workstreams

Respond ONLY with valid JSON matching the workplan schema, no markdown fences:
{{
  "workstreams": [...],
  "estimated_weeks": <number>,
  "summary": "<what changed and why>",
  "critical_path": [<workstream ids in order>]
}}"""
