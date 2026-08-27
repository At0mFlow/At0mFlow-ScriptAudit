# Usage and collection scope

## Default discovery

Without `-SearchPath` or `-ScanFixedDrives`, the collector checks non-Microsoft
PowerShell scheduled-task actions and these folders on each fixed drive when
they exist:

- `Scripts`
- `Automation`
- `PowerShell`
- `Ops`
- `Admin`
- `Tools`

```powershell
./src/Invoke-At0mFlowScriptAudit.ps1
```

## Explicit search paths

```powershell
./src/Invoke-At0mFlowScriptAudit.ps1 `
    -SearchPath C:\CompanyScripts, D:\Operations `
    -ExcludePath D:\Operations\Archive
```

## Full fixed-drive scan

```powershell
./src/Invoke-At0mFlowScriptAudit.ps1 -ScanFixedDrives
```

Known Windows, Program Files and system paths remain excluded. The scan skips
reparse points so it does not follow junctions into unexpected trees.

## Scheduled tasks

Scheduled-task discovery includes actions that execute `powershell.exe`,
`pwsh.exe` or a `.ps1` file. It records inline PowerShell actions even when no
script file can be copied.

Task folders under `\Microsoft\` are excluded by default:

```powershell
./src/Invoke-At0mFlowScriptAudit.ps1 -IncludeMicrosoftTaskFolder
```

Use that option only when built-in task context is genuinely needed.

## One-hour execution evidence

When scheduled-task discovery is enabled, the collector reads only the previous
hour from `Microsoft-Windows-TaskScheduler/Operational`. It records matching
action completion and launch failure evidence in
`manifests/script-run-evidence.csv`.

The account running the collector must be allowed to read that local Windows
event log. When several computers are collected over WinRM, the same check runs
inside each remote session against that computer's local event log. Nothing is
sent to At0mFlow or another service.

Task Scheduler history must be enabled by an administrator before collection.
The collector reports disabled or inaccessible logging but does not modify the
event log or local permissions.

The outcome rules are deliberately conservative:

- result code `0` from event 201 is `Succeeded`;
- a non-zero action result, task launch failure, logon failure or action start
  failure is `Failed`;
- Task Scheduler status constants are `SchedulerStatus`, not failures;
- no matching event is `Unknown`, never a presumed success;
- ambiguous multi-action task attribution is labelled in the CSV.

The collector never executes a discovered script to determine its status.

## Default locations

`-IncludeDefaultLocations` removes the standard Windows and Program Files path
exclusions. It does not disable paths supplied through `-ExcludePath`.

## File size

The default maximum copied script size is 25 MB:

```powershell
./src/Invoke-At0mFlowScriptAudit.ps1 -MaxFileSizeMB 50
```

Larger candidates remain visible in the inventory with a `TooLarge` status and
an accompanying collection error.

## Machine output and exit codes

Use `-Format Json` for a small summary on standard output or `-Quiet` for SCCM
and other deployment systems. Detailed results always live in the bundle.

| Code | Meaning |
| ---: | --- |
| `0` | Collection completed. Review the error CSV for non-fatal gaps. |
| `1` | `-FailOnCollectionError` was requested and gaps were recorded. |
| `2` | The collector could not start or complete its top-level operation. |
