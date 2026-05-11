# AI + Security News — sample configuration

This is the default Smart Briefing configuration: a curated AI + security news briefing aimed at a DevOps / platform engineer audience.

## What this configuration does

- **Models** — Stage 1 uses `openai/gpt-oss-120b` on Groq (fast, cheap, good enough at routing). Stage 2 uses `claude-haiku-4-5` on Anthropic (writes the summaries you actually read). See `docs/architecture.md` for the hybrid LLM rationale.
- **Window** — looks back 2 days. Most RSS publishers post once a day; 2 days catches everything without flooding.
- **Threshold** — `medium`. Articles scored `medium` or `high` survive to Stage 2; `low` articles are dropped without being summarized. Tighten to `high` for a stricter filter; loosen to `low` to see everything.
- **Keywords** — a broad AI + security keyword set. The keyword filter is a prefilter, not the relevance check — it removes obviously off-topic content cheaply before any LLM call. Stage 1 does the real relevance work.

## Loading this config

After OpenSearch is up and the `briefing-config` index template is applied:

```bash
curl -X POST "$OPENSEARCH_URL/briefing-config/_doc/default" \
     -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" \
     -H 'Content-Type: application/json' \
     -d @config/examples/ai-security-news/briefing-config.json
```

The workflow reads this document at the start of every run. Edit and re-POST to change behaviour; no workflow restart needed.

## Customizing

The fastest path to a personalized briefing:

1. Copy this directory: `cp -r config/examples/ai-security-news config/examples/my-topic`
2. Edit `keywords.ai` — replace with terms relevant to your topic. Whole-word case-insensitive match, so `"M&A"` matches `M&A` but not `MA` or `m&aing`.
3. Optionally tighten `relevance_threshold` and `window_days`.
4. Re-POST the document.

To swap **which feeds** are ingested, edit the `rssFeedRead` nodes inside the workflow itself (the n8n UI is the easiest path). Each feed has a small "Tag" node next to it that sets `source_name` — update that to match.

A future version moves feed selection into this config document so feeds, models, sections, and schedule are all editable without touching the workflow.
