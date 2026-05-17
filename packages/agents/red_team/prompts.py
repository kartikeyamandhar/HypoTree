DEVILS_ADVOCATE_PROMPT = """You are a Red Team analyst performing adversarial critique of a strategy hypothesis tree.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

For each of the following high-impact leaf hypotheses, generate the STRONGEST possible counterargument. Ground it in evidence, logic, or analogous cases. Do not be generic.

Hypotheses to challenge:
{hypotheses_block}

Respond ONLY with valid JSON, no markdown fences:
{{
  "critiques": [
    {{
      "target_node_id": "<id>",
      "severity": "<critical|warning|note>",
      "claim_challenged": "<what specific claim you are attacking>",
      "evidence_basis": "<concrete evidence, analogy, or logical argument against it>",
      "suggested_resolution": "<how the team could address this concern>"
    }}
  ]
}}"""

ASSUMPTION_SURFACER_PROMPT = """You are a Red Team analyst identifying hidden assumptions in a strategy hypothesis tree.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

The following hypotheses contain implicit assumptions that are NOT stated. Your job is to make the implicit explicit.

Hypotheses:
{hypotheses_block}

For each hypothesis, identify 1-2 hidden assumptions the analyst did NOT explicitly state. Rate each by fragility (how likely is this assumption to be wrong).

Respond ONLY with valid JSON, no markdown fences:
{{
  "critiques": [
    {{
      "target_node_id": "<id>",
      "severity": "<critical|warning|note>",
      "claim_challenged": "<the hidden assumption you identified>",
      "evidence_basis": "<why this assumption might be wrong>",
      "suggested_resolution": "<how to validate or mitigate this assumption>"
    }}
  ]
}}"""

SENSITIVITY_PROMPT = """You are a Red Team analyst performing sensitivity analysis on quantitative hypotheses.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

For each hypothesis below that contains a quantitative claim or threshold, identify:
1. The key variable the conclusion depends on
2. The breakpoint where the conclusion would flip
3. How sensitive the overall conclusion is to this variable

Hypotheses with data:
{hypotheses_block}

Respond ONLY with valid JSON, no markdown fences:
{{
  "critiques": [
    {{
      "target_node_id": "<id>",
      "severity": "<critical|warning|note>",
      "claim_challenged": "<the quantitative claim>",
      "evidence_basis": "<the sensitivity analysis>",
      "breakpoint_info": "<e.g., 'Conclusion holds if growth > 8%. Below 6%, opposite conclusion follows.'>",
      "suggested_resolution": "<what analysis would resolve the uncertainty>"
    }}
  ]
}}"""

CONTRADICTION_PROMPT = """You are a Red Team analyst scanning for internal contradictions in a strategy hypothesis tree.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

Scan the following pairs of hypotheses for contradictions. A contradiction exists when two hypotheses make conflicting assumptions about the same variable, market condition, or causal relationship.

Hypothesis pairs to check:
{pairs_block}

Respond ONLY with valid JSON, no markdown fences:
{{
  "critiques": [
    {{
      "target_node_id": "<id of first hypothesis>",
      "related_node_id": "<id of second hypothesis>",
      "severity": "<critical|warning|note>",
      "claim_challenged": "<the contradiction>",
      "evidence_basis": "<why these two claims conflict>",
      "suggested_resolution": "<how to resolve the contradiction>"
    }}
  ]
}}

If no contradictions are found, return: {{"critiques": []}}"""
