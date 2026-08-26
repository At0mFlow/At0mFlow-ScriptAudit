# Public repository boundary

At0mFlow Script Audit is a standalone, public collector. It is intentionally
separate from the At0mFlow product.

This repository may contain only:

- the open Windows PowerShell script collector in `src`;
- synthetic examples and tests;
- public documentation and repository configuration;
- approved At0mFlow brand assets.

It must not contain At0mFlow product code, prompts, scoring rules, cleanup or
migration logic, backend code, application configuration, credentials,
customer data, real server inventories or collected script estates.

## Generated bundle boundary

The tool writes a local audit bundle only after somebody runs it. That bundle
can contain source code, server names, file owners, task principals, paths and
scheduling details. It must be treated as confidential client material.

The tool does not initialise Git, create a remote, push a repository, upload to
At0mFlow or send telemetry. Generated bundle names are ignored by this public
repository's `.gitignore`.

## Automated controls

`scripts/Test-PublicBoundary.ps1` checks for unexpected paths, generated audit
bundles, private keys, credential patterns, identifying workstation paths,
symbolic links, unsuitable source types and an incorrect Git remote.

The check runs in GitHub Actions and through the repository's pre-commit and
pre-push hooks after they are enabled:

```powershell
git config core.hooksPath .githooks
```

Automated checks reduce accidental disclosure risk, but every staged change
still needs human review.
