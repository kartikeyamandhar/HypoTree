BENCHMARK_PROMPT = """You are a strategy consulting analyst finding comparable cases.

Context:
- Industry: {industry}
- Company: {company}
- Question: {question}

For the following hypothesis that contains a quantitative assumption, find analogous historical cases.

Hypothesis: "{statement}"
Assumption to benchmark: "{assumption}"

Available financial data:
{available_data}

Find 3-5 comparable situations (mergers, market entries, cost programs, etc.) from the same or adjacent industries. For each, provide:
- The company/entities involved
- What happened (brief)
- The relevant metric/outcome
- How it compares to the assumption being tested

Respond ONLY with valid JSON, no markdown fences:
{{
  "comparables": [
    {{
      "entities": "<companies involved>",
      "description": "<what happened, 1-2 sentences>",
      "metric": "<the relevant metric>",
      "value": "<actual outcome value>",
      "source": "<where this data comes from>",
      "relevance": "<how this compares to the assumption>"
    }}
  ],
  "distribution_summary": "<1-2 sentences: median, range, where the assumption falls>"
}}"""
