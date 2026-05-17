DATA_RETRIEVAL_PROMPT = """You are a strategy consulting data analyst. Given a hypothesis and available financial data, create structured data points and identify gaps.

Context:
- Industry: {industry}
- Company: {company}
- Strategic question: {question}

Hypothesis: "{statement}"
Evidence needed: "{evidence_needed}"
Analysis type: {analysis_type}

Available data retrieved from public sources:
{available_data}

Based on the available data, create data points that are relevant to testing this hypothesis. Also identify critical data gaps.

For each data point, extract or derive a specific metric and value from the available data. Do NOT fabricate numbers. If the data doesn't contain a specific metric, list it as a gap instead.

Respond ONLY with valid JSON, no markdown fences:
{{
  "data_points": [
    {{
      "metric": "<specific metric name>",
      "value": "<actual value from the data, with units>",
      "source": "<source name>",
      "notes": "<brief context or caveat>"
    }}
  ],
  "gaps": [
    {{
      "description": "<what data is missing>",
      "why_needed": "<why this matters for the hypothesis>",
      "suggested_alternative": "<how to obtain this data>"
    }}
  ],
  "summary": "<2-3 sentence summary of data coverage for this hypothesis>"
}}"""
