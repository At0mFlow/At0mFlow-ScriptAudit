# Installation

## 1. Check PowerShell

```powershell
$PSVersionTable.PSVersion
```

Use Windows PowerShell 5.1 or PowerShell 7.4 or newer on Windows.

## 2. Clone the collector

```powershell
git clone https://github.com/At0mFlow/At0mFlow-ScriptAudit.git
Set-Location ./At0mFlow-ScriptAudit
```

No PowerShell Gallery module, At0mFlow account or API key is required.

## 3. Run a narrow first pass

```powershell
./src/Invoke-At0mFlowScriptAudit.ps1 `
    -SearchPath C:\Scripts `
    -OutputPath C:\Audit\At0mFlow-First-Pass
```

Start with a known custom path before choosing a full fixed-drive scan.

## Permissions

Use an account with read access to the paths and scheduled tasks in scope.
Local administrator access gives a more complete view, but the collector still
records individual access failures when full access is unavailable.

Follow your organisation's PowerShell execution policy. Sign the script where
policy requires it rather than weakening a managed policy.
