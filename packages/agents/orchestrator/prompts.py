CLASSIFICATION_PROMPT = """You are a strategy consulting expert. Given a strategic question, classify it into exactly one category and select the appropriate decomposition framework.

Categories:
- growth_market_entry: Questions about entering new markets, expanding geographically, launching new products
- cost_optimization: Questions about reducing costs, improving efficiency, streamlining operations
- ma_rationale: Questions about mergers, acquisitions, divestitures, joint ventures
- pricing_strategy: Questions about pricing models, price changes, value capture
- competitive_response: Questions about responding to competitor actions, competitive positioning
- digital_transformation: Questions about technology investment, AI adoption, digital capabilities

Respond ONLY with valid JSON, no markdown fences:
{{
  "question_type": "<category>",
  "framework": "<framework>",
  "confidence": <0.0-1.0>,
  "rationale": "<one sentence>"
}}

Framework mapping:
- growth_market_entry -> 3cs_market_attractiveness
- cost_optimization -> value_chain_decomposition
- ma_rationale -> synergy_tree_standalone
- pricing_strategy -> value_based_pricing
- competitive_response -> game_theory_porters
- digital_transformation -> capability_maturity_roi

Strategic question:
Industry: {industry}
Company: {company}
Question: {question}"""

ROOT_HYPOTHESIS_PROMPT = """You are a strategy consulting expert building a hypothesis tree.

Context:
- Industry: {industry}
- Company: {company}
- Question: {question}
- Question Type: {question_type}
- Framework: {framework}

Generate the ROOT hypothesis and its FIRST-LEVEL children (3-5 branches). These first-level branches must be MECE (Mutually Exclusive, Collectively Exhaustive) — they should not overlap and together should cover the full scope of the question.

For each node provide:
- statement: the hypothesis
- what_must_be_true: what conditions validate this hypothesis
- evidence_needed: what data or analysis would prove/disprove it

Respond ONLY with valid JSON, no markdown fences:
{{
  "root": {{
    "statement": "<root hypothesis>",
    "what_must_be_true": "<condition>",
    "evidence_needed": "<evidence>"
  }},
  "children": [
    {{
      "statement": "<branch hypothesis>",
      "what_must_be_true": "<condition>",
      "evidence_needed": "<evidence>"
    }}
  ]
}}"""
