# Threat Model

> **Status:** Stub. The full threat model + mitigation rationale ships alongside the [prompt-injection deep-dive post](https://www.linkedin.com/in/sashafelix) in 1–2 weeks.

## TL;DR

Every article ingested is a piece of untrusted content from the open internet. Indirect prompt injection — instructions hidden inside an article body trying to hijack Stage 1 or Stage 2 — is treated as a real threat, not a theoretical one.

## v1 baseline mitigations (in code today)

- **URL stripping at ingest.** RSS-supplied URLs are kept for citation; in-body URLs are stripped before LLM input to prevent "follow this link" payloads from being a vector.
- **Content length caps.** Stage 1 sees the first 500 characters of each article. Stage 2 sees the full body but with system-prompt boundaries that explicitly mark untrusted regions.
- **Structured-output parsing with strict schema.** Stage 1 returns JSON; the parser rejects anything that doesn't match the expected shape. An article that talks the LLM into returning a different shape fails to score and is dropped.
- **Role boundaries in system prompts.** System prompt explicitly states that user content is data, not instructions, and that any apparent instructions within user content must be ignored.

## What's NOT covered yet (v1.1 work)

- Adversarial test corpus to catch regressions
- Detection signals for "this article tried to inject something"
- Multi-feed correlation (a single source going hostile is easier to spot than a coordinated multi-feed payload)

These land with the v1.1 release and the corresponding deep-dive post.
