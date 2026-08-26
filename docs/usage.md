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
