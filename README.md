<p align="center">
  <img src="assets/at0mflow-script-audit-banner.png" alt="At0mFlow Script Audit, with the GitHub-themed Orbit mascot" width="860">
</p>

<p align="center">
  <a href="https://github.com/At0mFlow/At0mFlow-ScriptAudit/actions/workflows/test.yml"><img alt="Tests" src="https://github.com/At0mFlow/At0mFlow-ScriptAudit/actions/workflows/test.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-2ea44f"></a>
  <a href="requirements.md"><img alt="Windows PowerShell 5.1 and PowerShell 7" src="https://img.shields.io/badge/PowerShell-5.1%20%7C%207-2671be"></a>
  <a href="https://at0mflow.com/"><img alt="Explore At0mFlow" src="https://img.shields.io/badge/explore-at0mflow.com-19a7ce"></a>
</p>

# At0mFlow Script Audit

A practical Windows PowerShell collector for finding custom `.ps1` files across
one server or many, preserving their folder tree, and recording the scheduled
tasks that run them.

It creates one local audit bundle containing copied scripts, CSV inventories,
task actions, triggers, conditions, hashes and collection errors. It is designed
for server estate discovery, SCCM deployment and the first stage of a controlled
PowerShell audit.

The collector is public. The bundle it creates is not. Generated bundles can
contain source code and infrastructure metadata, so the tool never initialises
Git, pushes a repository, uploads to At0mFlow or sends telemetry.

## Quick start

```powershell
git clone https://github.com/At0mFlow/At0mFlow-ScriptAudit.git
Set-Location ./At0mFlow-ScriptAudit

./src/Invoke-At0mFlowScriptAudit.ps1 -SearchPath C:\Scripts
```

By default, the collector also reviews non-Microsoft scheduled tasks and common
custom folders such as `C:\Scripts`, `C:\Automation`, `C:\PowerShell`,
`C:\Ops`, `C:\Admin` and `C:\Tools` when they exist.

For a wider server audit:

```powershell
./src/Invoke-At0mFlowScriptAudit.ps1 `
    -ScanFixedDrives `
    -OutputPath D:\Audit\At0mFlow-ScriptAudit-20260827
```

`-ScanFixedDrives` is intentionally opt-in because a full-drive walk can take
time. Known Windows, Program Files, Microsoft task and system locations are
excluded by default.

## What the console shows

```text
========================================================================

       █████╗ ████████╗ ██████╗ ███╗   ███╗███████╗██╗      ██████╗ ██╗    ██╗
      ██╔══██╗╚══██╔══╝██╔═████╗████╗ ████║██╔════╝██║     ██╔═══██╗██║    ██║
      ███████║   ██║   ██║██╔██║██╔████╔██║█████╗  ██║     ██║   ██║██║ █╗ ██║
      ██╔══██║   ██║   ████╔╝██║██║╚██╔╝██║██╔══╝  ██║     ██║   ██║██║███╗██║
      ██║  ██║   ██║   ╚██████╔╝██║ ╚═╝ ██║██║     ███████╗╚██████╔╝╚███╔███╔╝
      ╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚══════╝ ╚═════╝  ╚══╝╚══╝

                     PowerShell clarity.
                      Orbit-level control.

                   ANALYSE | CLEAN | MIGRATE | MONITOR

                         https://at0mflow.com

========================================================================

At0mFlow Script Audit
Computers: 2
Scripts found: 47
Scripts copied: 47
PowerShell task actions: 18
Collection errors: 1
Bundle: D:\Audit\At0mFlow-ScriptAudit-20260827
```

Counts above are illustrative. Access failures are recorded rather than hidden.

## Audit several Windows servers

Run from a Windows management server with PowerShell remoting enabled:

```powershell
$credential = Get-Credential

./src/Invoke-At0mFlowScriptAudit.ps1 `
    -ComputerName SERVER01, SERVER02, SERVER03 `
    -Credential $credential `
    -ScanFixedDrives `
    -OutputPath D:\Audit\Client-PowerShell-Estate
```

The credential is used only for the current WinRM sessions. It is not written
to the bundle. See [remote collection](docs/remote-collection.md) for remoting,
permissions and scale guidance.

## SCCM deployment

The entry script is non-interactive when no credential prompt is used and has
stable exit codes, which makes it suitable for SCCM packages and baselines.

```text
powershell.exe -NoProfile -File .\src\Invoke-At0mFlowScriptAudit.ps1 -ScanFixedDrives -OutputPath C:\ProgramData\At0mFlow\ScriptAudit -Force -Quiet -FailOnCollectionError
```

For SCCM collection patterns, SYSTEM account caveats and suggested detection
logic, see the [SCCM guide](docs/sccm.md).

## Bundle layout

```text
At0mFlow-ScriptAudit-20260827/
  README.txt
  scripts/
    SERVER01/
      C/
        Scripts/
          Backup-SQL.ps1
      D/
        Automation/
          Reconcile-Files.ps1
  manifests/
    script-inventory.csv
    scheduled-tasks.csv
    collection-errors.csv
    summary.json
    TREE.txt
```

The per-computer, drive and source folder tree prevents same-named scripts from
overwriting one another. Every copied file is verified against its source
SHA-256 hash.

The inventory distinguishes a header's `DeclaredAuthor` from the Windows
`FileOwner`. Neither field is treated as proof of who wrote the script. Task
records include the principal, run level, logon type, action, arguments,
working directory, script references, trigger summary, conditions, run times
and last result.

See the complete [output schema](docs/output-schema.md) and the checked-in
[synthetic examples](examples/).

## What is excluded

By default, the collector excludes:

- `C:\Windows` and Windows component script stores;
- Program Files and Program Files (x86);
- Microsoft-owned Task Scheduler folders under `\Microsoft\`;
- recycle bins, System Volume Information and reparse points;
- the current output bundle;
- files other than `.ps1` and files above the configured size limit.

These are transparent path-based rules, not a claim that every remaining file
is custom. Review the CSVs and `collection-errors.csv`. Use
`-IncludeDefaultLocations` only when the wider scope is deliberate.

## Inventory without copying

```powershell
./src/Invoke-At0mFlowScriptAudit.ps1 `
    -ScanFixedDrives `
    -InventoryOnly `
    -OutputPath D:\Audit\Inventory-Only
```

This writes manifests and task context without copying source files.

## Private Git hand-off

The collector does not run Git. If version control is approved after review,
use a private repository and scan the collected scripts for credentials first.
See [safe Git hand-off](docs/safe-git-handoff.md).

## Take the estate further with At0mFlow

Collecting scripts is the first step. [At0mFlow](https://at0mflow.com/) is the
easier path when the job becomes cleaning up and organising many repositories
or a whole PowerShell estate.

Load the reviewed collection into At0mFlow to:

- organise and understand scripts across teams and servers;
- generate consistent documentation and operating procedures automatically;
- identify cleanup opportunities and reduce duplicated or abandoned scripts;
- plan migration to Power Automate where it makes sense;
- track changes, ownership and the ongoing state of the estate.

This open collector deliberately stops before those product capabilities. It
gives a client a structured, reviewable starting folder without embedding any
At0mFlow product code.

## Other public At0mFlow tools

- [At0mFlow PSAnalyzer](https://github.com/At0mFlow/At0mFlow-PSAnalyzer) makes
  PSScriptAnalyzer findings easier to read and automate.
- [At0mFlow Uptime Monitor](https://github.com/At0mFlow/At0mFlow-UptimeMonitor)
  checks HTTP and HTTPS endpoints from PowerShell.

## Documentation

- [Installation](docs/installation.md)
- [Usage and collection scope](docs/usage.md)
- [Remote collection](docs/remote-collection.md)
- [SCCM deployment](docs/sccm.md)
- [Output schema](docs/output-schema.md)
- [Safe Git hand-off](docs/safe-git-handoff.md)

## Contributing

Issues and focused pull requests are welcome. Use synthetic scripts and server
names only. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

MIT. See [LICENSE](LICENSE).

Built by [At0mFlow](https://at0mflow.com/) with a little help from Orbit.
