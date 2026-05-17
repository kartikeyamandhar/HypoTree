DECOMPOSE_PROMPT = """You are a strategy consulting expert. Decompose the given hypothesis into 2-4 sub-hypotheses that are MECE (Mutually Exclusive, Collectively Exhaustive).

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

Parent hypothesis: "{parent_statement}"
Current depth: {depth} (target max depth: {target_depth})

{issues_section}

Generate 2-4 sub-hypotheses. Each must be:
- Mutually exclusive: no overlap in scope with siblings
- Collectively exhaustive: together they fully cover the parent hypothesis
- Specific and testable: not vague or generic
- At the right level of detail for depth {next_depth}

Respond ONLY with valid JSON, no markdown fences:
{{
  "children": [
    {{
      "statement": "<sub-hypothesis>",
      "what_must_be_true": "<what condition validates this>",
      "evidence_needed": "<what data proves/disproves this>"
    }}
  ]
}}"""

ISSUES_TEMPLATE = """Previous decomposition had issues:
- Overlaps: {overlaps}
- Gaps: {gaps}
- Suggestions: {suggestions}

Fix these issues in the new decomposition."""
