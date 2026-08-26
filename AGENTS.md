# Public repository boundary

Use Australian English. Write clearly, naturally and concisely. Never use em
dashes.

This repository is public and contains only the standalone At0mFlow Script
Audit collector, its tests, synthetic examples, documentation and brand assets.

## Non-negotiable separation rules

- Never copy code, prompts, rules, configuration, schemas, data or assets from
  the At0mFlow product repository into this repository, except approved public
  brand assets.
- Never add At0mFlow scoring, AI analysis, code rewriting, cleanup, migration,
  backend, authentication, billing or customer-data logic.
- Never add collected client scripts, task exports, server inventories or audit
  bundles to this repository.
- Never initialise, commit, sync or push a client's collected scripts. The tool
  may only write the requested local audit bundle.
- Never add telemetry or upload audit results to At0mFlow or another service.
- Never stage files from outside this repository.
- Keep `origin` pointed only to
  `https://github.com/At0mFlow/At0mFlow-ScriptAudit.git` or its equivalent
  GitHub SSH URL.
- Use synthetic examples and fixtures only.
- Before every commit and push, run `./scripts/Test-PublicBoundary.ps1` and
  `./tests/Run-Tests.ps1`.
- Stop if the boundary check fails. Do not bypass or weaken it without reviewing
  the flagged content.
