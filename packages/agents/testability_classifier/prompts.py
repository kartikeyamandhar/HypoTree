TESTABILITY_PROMPT = """You are a strategy consulting analyst classifying the testability of hypotheses.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

For the following leaf hypothesis, classify its testability and assign priority scores.

Hypothesis: "{statement}"
What must be true: "{what_must_be_true}"
Evidence needed: "{evidence_needed}"

Classifications:
- quantitative: Can be tested with data analysis (market data, financials, surveys, metrics)
- qualitative: Requires expert interviews, primary research, or qualitative judgment
- assumption: Requires team alignment or client input; not externally verifiable
- already_answered: Public data exists that resolves this hypothesis now

Scoring:
- impact_score (1-5): How much does this hypothesis matter to the overall answer?
- testability_score (1-3): How feasible is it to test this hypothesis? 3=easy, 1=hard
- data_availability_score (1-3): How available is the needed data? 3=public, 1=proprietary/unavailable

Respond ONLY with valid JSON, no markdown fences:
{{
  "classification": "<quantitative|qualitative|assumption|already_answered>",
  "confidence": <0.0-1.0>,
  "rationale": "<one sentence explaining classification>",
  "impact_score": <1-5>,
  "testability_score": <1-3>,
  "data_availability_score": <1-3>
}}"""
