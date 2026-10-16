Write a session title as `<CODE>: <title>`.

CODE:
- If the conversation names an issue key such as ABC-123 or XY-42, CODE is that key without the hyphen: ABC123, XY42.
- Otherwise CODE is exactly one of: PR, EXPLAIN, TRIAGE, PLAN, BUILD, OMP, OPS, MISC.
  PR = review a pull request or address its comments. EXPLAIN = explain a plan, PR, ticket, code or design.
  TRIAGE = investigate a bug, failed build or failed test. PLAN = write a plan, spec or design.
  BUILD = implement a change with no issue key. OMP = omp, Tern or local tooling.
  OPS = deploys, infrastructure, environments. MISC = anything else.

title: 3 to 7 words, imperative, no trailing period.
Output only the title line.
