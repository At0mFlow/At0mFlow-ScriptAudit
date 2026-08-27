# SCCM deployment

At0mFlow Script Audit can run locally on each managed Windows server through an
SCCM package, application or compliance workflow.

## Suggested command

```text
powershell.exe -NoProfile -File .\src\Invoke-At0mFlowScriptAudit.ps1 -ScanFixedDrives -OutputPath C:\ProgramData\At0mFlow\ScriptAudit -Force -Quiet -FailOnCollectionError
```

This produces no interactive banner and returns a non-zero code when collection
gaps are present.

## SYSTEM account considerations

- Local SYSTEM usually has broad local read access.
- It does not automatically have access to a remote UNC share.
- A share may need to authorise the computer account, a managed service account
  or another approved execution identity.
- Writing locally and letting SCCM collect the bundle is often simpler than
  writing directly to a network share.
- Reading one-hour execution evidence requires local access to the Task
  Scheduler Operational event log. Grant only the event-log permission needed
  by the approved SCCM execution identity.

## Detection and collection

Use `manifests/summary.json` as the completion artefact. Check its timestamp,
`ErrorCount` and `HasErrors` values before marking the audit successful.

Collect the whole output folder, not only the copied scripts. The CSVs provide
the task and provenance context needed during estate review.

`script-run-evidence.csv` contains only the previous hour of local Task
Scheduler evidence. Disabled or inaccessible logging is recorded as unavailable
evidence rather than success or failure.

## Reruns

Use a new timestamped path for immutable audit evidence. `-Force` is available
for managed reruns into a known folder, but it does not delete unrelated files.
