# Contributing

Small, focused improvements are welcome.

1. Fork the repository and create a branch.
2. Keep the collector independent of At0mFlow product code and services.
3. Use synthetic scripts, computer names, paths and task data in every fixture.
4. Never contribute a generated client audit bundle.
5. Run `./tests/Run-Tests.ps1` on Windows.
6. Analyse `./src` with PSScriptAnalyzer errors and warnings enabled.
7. Open a pull request explaining the behaviour and safety impact.

Please do not submit credentials, internal server names, customer scripts,
private endpoints, AI prompts, scoring systems, migration logic or other
confidential material.
