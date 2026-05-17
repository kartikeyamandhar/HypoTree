MECE_VALIDATION_PROMPT = """You are a MECE validator for strategy consulting hypothesis trees.

Check whether the sibling hypotheses are reasonably MECE:
- Mutually Exclusive: siblings should address distinct aspects with minimal overlap. Minor thematic connections are acceptable — flag only significant scope overlaps.
- Collectively Exhaustive: siblings should cover the most important dimensions of the parent. They don't need to cover every conceivable angle — flag only critical missing dimensions.

Parent hypothesis: "{parent_statement}"

Sibling hypotheses:
{siblings_list}

Be practical, not perfectionist. A decomposition is valid if it covers the major dimensions without significant duplication. Minor overlaps in real-world strategy work are normal.

Respond ONLY with valid JSON, no markdown fences:
{{
  "is_valid": true,
  "overlaps": [],
  "gaps": [],
  "suggestions": []
}}

Set is_valid to false ONLY if there are major structural problems — significant scope duplication or a critical dimension entirely missing."""
