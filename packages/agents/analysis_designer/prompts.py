ANALYSIS_DESIGN_PROMPT = """You are a strategy consulting analyst designing analysis methodologies.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

For the following hypothesis classified as "{testability_class}", design an appropriate analysis.

Hypothesis: "{statement}"
What must be true: "{what_must_be_true}"
Evidence needed: "{evidence_needed}"

Available analysis types:
- regression: Statistical regression on historical data
- benchmarking: Compare against industry peers or best practices
- cohort_analysis: Segment-based analysis of customer or market groups
- scenario_modeling: Build scenarios with different assumptions
- break_even: Determine threshold values for viability
- market_sizing: Top-down or bottom-up market size estimation
- competitive_analysis: Analyze competitor positioning and responses
- financial_modeling: Build financial projections (DCF, multiples, etc.)
- survey_analysis: Design and analyze primary research surveys
- expert_interviews: Structure and synthesize expert interview findings
- case_study: Analyze analogous historical cases
- data_analysis: General quantitative analysis of available datasets
- cost_analysis: Detailed cost structure and optimization analysis
- sensitivity_analysis: Test sensitivity of conclusions to key assumptions

Choose the MOST appropriate analysis type. Do NOT choose expert_interviews or survey_analysis for quantitative hypotheses. Do NOT choose regression or financial_modeling for qualitative hypotheses.

For data_sources, list 3-5 specific, realistic sources (e.g., "SEC 10-K filings", "Euromonitor travel market reports", "SimilarWeb traffic data").

For loe_hours, estimate realistic analyst-hours: simple analyses 4-8h, moderate 8-20h, complex 20-40h.

Respond ONLY with valid JSON, no markdown fences:
{{
  "analysis_type": "<type>",
  "methodology": "<2-3 sentence description of specific analytical approach>",
  "data_sources": ["<source1>", "<source2>", "<source3>"],
  "output_format": "<chart type or deliverable format, e.g., 'Waterfall chart showing synergy breakdown'>",
  "loe_hours": <number>,
  "rationale": "<one sentence on why this analysis type fits>"
}}"""
