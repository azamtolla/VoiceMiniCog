---
name: llm-council
description: Multi-model deliberation for high-stakes decisions. Use when asked to "council" a question or when prefixed with /council.
---

# LLM Council — Multi-Model Deliberation

When the user invokes this skill, execute the following 3-phase process:

## Phase 1: Independent Responses

Send the user's question to 5 different "advisors" by running the council script:

```bash
python3 .claude/skills/llm-council/council.py --question "$QUESTION"
```

Each advisor has a distinct thinking style:
1. **The Pragmatist** — What's the fastest path that works?
2. **The Skeptic** — What could go wrong? What are we missing?
3. **The Researcher** — What does evidence/best practice say?
4. **The User Advocate** — How does the end user (clinician/patient) experience this?
5. **The Architect** — How does this affect the system long-term?

## Phase 2: Anonymous Peer Review

Each model reviews all 5 anonymized responses and ranks them 1-5 with reasoning.

## Phase 3: Chairman Synthesis

Read all responses and all reviews. Produce:
- **Verdict**: The synthesized best answer
- **Consensus points**: Where all advisors agreed
- **Dissent points**: Where they disagreed and why it matters
- **Risk flags**: Anything 2+ advisors flagged as dangerous
- **Recommendation**: Final actionable advice

Format the output clearly with headers and present it to the user.
