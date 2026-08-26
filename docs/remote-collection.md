# Remote collection

At0mFlow Script Audit uses standard PowerShell remoting for server-to-server
collection. It does not install an agent.

## Prerequisites

- Run the collector from Windows.
- Enable and approve WinRM according to the organisation's security policy.
- Make sure DNS, firewall and authentication settings allow the management
  server to create a PowerShell session to each target.
- Use an account with the required read access.

## Current credentials

For domain-connected servers where the current account already has access:

```powershell
./src/Invoke-At0mFlowScriptAudit.ps1 `
    -ComputerName SERVER01, SERVER02 `
    -ScanFixedDrives `
    -OutputPath D:\Audit\Server-Estate
```

## Supplied credential

```powershell
$credential = Get-Credential

./src/Invoke-At0mFlowScriptAudit.ps1 `
    -ComputerName SERVER01, SERVER02 `
    -Credential $credential `
    -ScanFixedDrives `
    -OutputPath D:\Audit\Server-Estate
```

The `PSCredential` is passed to `New-PSSession` for the current run only. It is
never exported.

## Scaling guidance

The collector processes computers one at a time. This is deliberate: it keeps
network load predictable, makes per-server errors readable and avoids pulling
large script estates concurrently across management links.

For very large estates, divide targets into approved batches and give each batch
its own output folder. Merge only after reviewing errors and duplicate hashes.

## Double-hop and UNC paths

A scheduled task may reference a UNC path that the remoting identity cannot
read because of Kerberos delegation or share permissions. The collector records
the missing source rather than changing authentication settings. Resolve access
through the organisation's approved remoting design.
