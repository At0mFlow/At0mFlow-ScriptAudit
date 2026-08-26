[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:FailureCount = 0

function Assert-That {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if ($Condition) {
        Write-Host "PASS: $Message" -ForegroundColor Green
    }
    else {
        $script:FailureCount++
        Write-Host "FAIL: $Message" -ForegroundColor Red
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'src/At0mFlow.ScriptAudit/At0mFlow.ScriptAudit.psd1'
$entryPoint = Join-Path $repositoryRoot 'src/Invoke-At0mFlowScriptAudit.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('At0mFlow-ScriptAudit-Tests-' + [guid]::NewGuid())

try {
    $manifest = Test-ModuleManifest -Path $modulePath
    Assert-That ($manifest.Version.ToString() -eq '1.0.0') 'The module manifest is valid.'

    Import-Module $modulePath -Force

    $quotedReference = @(
        Get-At0mFlowTaskScriptReference `
            -Execute 'powershell.exe' `
            -Arguments '-NoProfile -File "C:\Ops\Nightly Backup.ps1"'
    )
    Assert-That ($quotedReference.Count -eq 1) 'A quoted task script reference is found once.'
    Assert-That ($quotedReference[0] -eq 'C:\Ops\Nightly Backup.ps1') 'Quoted paths preserve spaces.'

    $commandReference = @(
        Get-At0mFlowTaskScriptReference `
            -Execute 'pwsh.exe' `
            -Arguments "-Command & 'D:\Scripts\Rotate.ps1'"
    )
    Assert-That ($commandReference[0] -eq 'D:\Scripts\Rotate.ps1') 'Single-quoted command references are found.'

    $relativeReference = @(
        Get-At0mFlowTaskScriptReference `
            -Execute 'powershell.exe' `
            -Arguments '-File .\Health.ps1' `
            -WorkingDirectory 'C:\Automation'
    )
    Assert-That ($relativeReference[0] -eq 'C:\Automation\Health.ps1') 'Relative references use the task working directory.'

    $previousTestRoot = $env:AT0MFLOW_SCRIPT_AUDIT_TEST_ROOT
    try {
        $env:AT0MFLOW_SCRIPT_AUDIT_TEST_ROOT = 'C:\Synthetic'
        $environmentReference = @(
            Get-At0mFlowTaskScriptReference `
                -Execute 'powershell.exe' `
                -Arguments '-File "%AT0MFLOW_SCRIPT_AUDIT_TEST_ROOT%\Environment.ps1"'
        )
        Assert-That ($environmentReference[0] -eq 'C:\Synthetic\Environment.ps1') 'Environment variables in task paths are expanded.'
    }
    finally {
        $env:AT0MFLOW_SCRIPT_AUDIT_TEST_ROOT = $previousTestRoot
    }

    $unrelatedReference = @(
        Get-At0mFlowTaskScriptReference `
            -Execute 'cmd.exe' `
            -Arguments '/c example.cmd'
    )
    Assert-That ($unrelatedReference.Count -eq 0) 'Non-PowerShell actions do not invent script references.'

    $drivePath = ConvertTo-At0mFlowCentralPath `
        -ComputerName 'SERVER-EXAMPLE-01' `
        -OriginalPath 'C:\Scripts\Backup.ps1'
    Assert-That ($drivePath -eq 'scripts/SERVER-EXAMPLE-01/C/Scripts/Backup.ps1') 'Drive paths preserve their source tree.'

    $uncPath = ConvertTo-At0mFlowCentralPath `
        -ComputerName 'SERVER-EXAMPLE-01' `
        -OriginalPath '\\FILE-EXAMPLE\Ops\Scripts\Backup.ps1'
    Assert-That ($uncPath -eq 'scripts/SERVER-EXAMPLE-01/UNC/FILE-EXAMPLE/Ops/Scripts/Backup.ps1') 'UNC paths preserve server and share context.'

    $runningOnWindows = ($env:OS -eq 'Windows_NT') -or ($PSVersionTable.PSEdition -eq 'Desktop')
    if ($runningOnWindows) {
        New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
        $sourceRoot = Join-Path $temporaryRoot 'Synthetic Source'
        $excludedRoot = Join-Path $sourceRoot 'Excluded'
        New-Item -ItemType Directory -Path $excludedRoot -Force | Out-Null

        $sourcePath = Join-Path $sourceRoot 'Synthetic-NightlyReport.ps1'
        @(
            '# Author: Example Automation Team'
            '[pscustomobject] @{ Status = ''Synthetic only'' }'
        ) | Set-Content -LiteralPath $sourcePath -Encoding UTF8
        @(
            '# Author: Example Archive Team'
            'Write-Output ''Excluded synthetic fixture'''
        ) | Set-Content -LiteralPath (Join-Path $excludedRoot 'Archived.ps1') -Encoding UTF8

        $bundlePath = Join-Path $temporaryRoot 'Bundle'
        $report = Invoke-At0mFlowScriptAudit `
            -ComputerName 'localhost' `
            -SearchPath $sourceRoot `
            -ExcludePath $excludedRoot `
            -SkipScheduledTasks `
            -OutputPath $bundlePath

        Assert-That ($report.ScriptCount -eq 1) 'A local custom search path is collected.'
        Assert-That ($report.CopiedCount -eq 1) 'A discovered script is copied.'
        Assert-That (-not $report.HasErrors) 'A complete synthetic collection has no errors.'
        Assert-That ($report.Scripts[0].DeclaredAuthor -eq 'Example Automation Team') 'A declared author header is recorded.'
        Assert-That ($report.Scripts[0].CopyStatus -eq 'Copied') 'The manifest records a verified copy.'

        $copiedPath = Join-Path $bundlePath ($report.Scripts[0].CentralRelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        Assert-That (Test-Path -LiteralPath $copiedPath -PathType Leaf) 'The copied script exists in the central tree.'
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $copiedHash = (Get-FileHash -LiteralPath $copiedPath -Algorithm SHA256).Hash
        Assert-That ($sourceHash -eq $copiedHash) 'The copied script hash matches its source.'

        $scriptInventoryPath = Join-Path $bundlePath 'manifests/script-inventory.csv'
        $taskInventoryPath = Join-Path $bundlePath 'manifests/scheduled-tasks.csv'
        $summaryPath = Join-Path $bundlePath 'manifests/summary.json'
        $treePath = Join-Path $bundlePath 'manifests/TREE.txt'
        Assert-That (Test-Path -LiteralPath $scriptInventoryPath) 'The script inventory CSV is written.'
        Assert-That (Test-Path -LiteralPath $taskInventoryPath) 'An empty scheduled-task CSV keeps its schema.'
        Assert-That (Test-Path -LiteralPath $summaryPath) 'The JSON summary is written.'
        Assert-That ((Get-Content -LiteralPath $treePath -Raw) -match 'Synthetic-NightlyReport\.ps1') 'The folder tree lists the copied script.'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $bundlePath '.git'))) 'The collector does not initialise Git.'

        $inventoryBundlePath = Join-Path $temporaryRoot 'Inventory Bundle'
        $inventoryReport = Invoke-At0mFlowScriptAudit `
            -ComputerName 'localhost' `
            -SearchPath $sourceRoot `
            -ExcludePath $excludedRoot `
            -SkipScheduledTasks `
            -InventoryOnly `
            -OutputPath $inventoryBundlePath
        Assert-That ($inventoryReport.ScriptCount -eq 1) 'Inventory-only mode still records scripts.'
        Assert-That ($inventoryReport.CopiedCount -eq 0) 'Inventory-only mode copies no scripts.'
        Assert-That ($inventoryReport.Scripts[0].CopyStatus -eq 'InventoryOnly') 'Inventory-only status is explicit.'
        $inventoryScripts = @(Get-ChildItem -LiteralPath (Join-Path $inventoryBundlePath 'scripts') -Filter '*.ps1' -Recurse -File)
        Assert-That ($inventoryScripts.Count -eq 0) 'Inventory-only mode leaves the scripts tree empty.'

        $consoleBundlePath = Join-Path $temporaryRoot 'Console Bundle'
        $consoleText = & $entryPoint `
            -ComputerName 'localhost' `
            -SearchPath $sourceRoot `
            -ExcludePath $excludedRoot `
            -SkipScheduledTasks `
            -OutputPath $consoleBundlePath `
            -Format Console 6>&1 | Out-String
        Assert-That ($LASTEXITCODE -eq 0) 'The entry script exits successfully.'
        $block = [string] [char] 0x2588
        $logoFragment = '       ' + (($block * 5) -join '') + [char] 0x2557
        Assert-That $consoleText.Contains($logoFragment) 'Interactive output renders the At0mFlow block wordmark.'
        Assert-That ($consoleText -match 'At0mFlow Script Audit') 'Interactive output identifies the collector.'
        Assert-That ($consoleText -match 'Treat the bundle as confidential') 'Interactive output includes the privacy warning.'

        $jsonBundlePath = Join-Path $temporaryRoot 'JSON Bundle'
        $jsonText = & $entryPoint `
            -ComputerName 'localhost' `
            -SearchPath $sourceRoot `
            -ExcludePath $excludedRoot `
            -SkipScheduledTasks `
            -OutputPath $jsonBundlePath `
            -Format Json 6>&1 | Out-String
        $jsonReport = $jsonText | ConvertFrom-Json
        Assert-That ($LASTEXITCODE -eq 0) 'JSON output exits successfully.'
        Assert-That ($jsonReport.ScriptCount -eq 1) 'JSON output contains the bundle summary.'
        Assert-That ($jsonText -notmatch 'PowerShell clarity\.') 'JSON output does not include console branding.'

        $failureBundlePath = Join-Path $temporaryRoot 'Failure Bundle'
        & $entryPoint `
            -ComputerName 'localhost' `
            -SearchPath (Join-Path $temporaryRoot 'Missing Source') `
            -SkipScheduledTasks `
            -OutputPath $failureBundlePath `
            -Quiet `
            -FailOnCollectionError | Out-Null
        Assert-That ($LASTEXITCODE -eq 1) 'Collection gaps can fail an SCCM or CI run.'
    }
    else {
        Write-Host 'SKIP: Windows collection integration tests require Windows.' -ForegroundColor Yellow
    }
}
finally {
    $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemporaryRoot) -like 'At0mFlow-ScriptAudit-Tests-*' -and
        (Test-Path -LiteralPath $resolvedTemporaryRoot)) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}

if ($script:FailureCount -gt 0) {
    throw "$script:FailureCount test assertion(s) failed."
}

Write-Host 'All tests passed.' -ForegroundColor Cyan
exit 0
