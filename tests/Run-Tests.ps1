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
    Assert-That ($manifest.Version.ToString() -eq '1.1.1') 'The module manifest is valid.'

    Import-Module $modulePath -Force
    $moduleInstance = Get-Module At0mFlow.ScriptAudit

    $successfulOutcome = & $moduleInstance {
        Get-At0mFlowTaskEventOutcome -EventId 201 -ResultCode '0'
    }
    $failedOutcome = & $moduleInstance {
        Get-At0mFlowTaskEventOutcome -EventId 201 -ResultCode '2147942401'
    }
    $schedulerStatusOutcome = & $moduleInstance {
        Get-At0mFlowTaskEventOutcome -EventId 201 -ResultCode '0x00041301'
    }
    $negativeFailureOutcome = & $moduleInstance {
        Get-At0mFlowTaskEventOutcome -EventId 201 -ResultCode '-1'
    }
    $launchFailureOutcome = & $moduleInstance {
        Get-At0mFlowTaskEventOutcome -EventId 101 -ResultCode ''
    }
    Assert-That ($successfulOutcome -eq 'Succeeded') 'A zero Task Scheduler action result is successful evidence.'
    Assert-That ($failedOutcome -eq 'Failed') 'A non-zero action result is failure evidence.'
    Assert-That ($schedulerStatusOutcome -eq 'SchedulerStatus') 'A Task Scheduler status constant is not mislabelled as a failure.'
    Assert-That ($negativeFailureOutcome -eq 'Failed') 'A negative action result is failure evidence.'
    Assert-That ($launchFailureOutcome -eq 'Failed') 'A Task Scheduler launch failure is failure evidence.'

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
        Assert-That ($report.Scripts[0].CollectionChange -eq 'Added') 'A first collection records an added copy.'
        Assert-That ($report.Scripts[0].SourcePhysicalPath -eq $sourcePath) 'The physical source path is recorded.'
        Assert-That ([string]::IsNullOrWhiteSpace($report.Scripts[0].RepositoryRelativePath)) 'A non-Git bundle does not invent a repository path.'

        $copiedPath = Join-Path $bundlePath ($report.Scripts[0].CentralRelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        Assert-That (Test-Path -LiteralPath $copiedPath -PathType Leaf) 'The copied script exists in the central tree.'
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $copiedHash = (Get-FileHash -LiteralPath $copiedPath -Algorithm SHA256).Hash
        Assert-That ($sourceHash -eq $copiedHash) 'The copied script hash matches its source.'

        $scriptInventoryPath = Join-Path $bundlePath 'manifests/script-inventory.csv'
        $taskInventoryPath = Join-Path $bundlePath 'manifests/scheduled-tasks.csv'
        $summaryPath = Join-Path $bundlePath 'manifests/summary.json'
        $treePath = Join-Path $bundlePath 'manifests/TREE.txt'
        $executionEvidencePath = Join-Path $bundlePath 'manifests/script-run-evidence.csv'
        Assert-That (Test-Path -LiteralPath $scriptInventoryPath) 'The script inventory CSV is written.'
        Assert-That (Test-Path -LiteralPath $taskInventoryPath) 'An empty scheduled-task CSV keeps its schema.'
        Assert-That (Test-Path -LiteralPath $summaryPath) 'The JSON summary is written.'
        Assert-That (Test-Path -LiteralPath $executionEvidencePath) 'The one-hour execution evidence CSV is written.'
        $executionEvidence = @(Import-Csv -LiteralPath $executionEvidencePath)
        Assert-That ($executionEvidence.Count -eq 1) 'Every discovered script receives an execution-evidence row.'
        Assert-That ($executionEvidence[0].EvidenceStatus -eq 'NoScheduledTaskReference') 'A script without a task is not given an invented run result.'
        Assert-That ($executionEvidence[0].Outcome -eq 'Unknown') 'Missing execution evidence remains unknown.'
        $summaryData = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        Assert-That ($summaryData.ExecutionEvidenceLookbackHours -eq 1) 'Execution evidence is limited to the last hour.'
        Assert-That ((Get-Content -LiteralPath $treePath -Raw) -match 'Synthetic-NightlyReport\.ps1') 'The folder tree lists the copied script.'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $bundlePath '.git'))) 'The collector does not initialise Git.'

        $syntheticTaskEvidence = [pscustomobject] @{
            ComputerName             = $report.Scripts[0].ComputerName
            TaskName                  = 'Synthetic evidence task'
            TaskPath                  = '\Operations\'
            ActionExecute             = 'powershell.exe'
            IncludedScriptReferences  = $sourcePath
        }
        $syntheticFailureEvent = [pscustomobject] @{
            ComputerName = $report.Scripts[0].ComputerName
            EventTimeUtc  = '2026-08-27T02:30:00.0000000Z'
            EventId       = 201
            EventRecordId = 12345
            TaskName      = '\Operations\Synthetic evidence task'
            ActionName    = 'powershell.exe'
            ResultCode    = '1'
        }
        $observedEvidence = @(& $moduleInstance {
            param($ScriptRow, $TaskRow, $EventRow)
            ConvertTo-At0mFlowExecutionEvidence `
                -Scripts @($ScriptRow) `
                -Tasks @($TaskRow) `
                -TaskEvents @($EventRow) `
                -EventLogStatus 'Available' `
                -LookbackStartUtc '2026-08-27T02:00:00.0000000Z' `
                -LookbackEndUtc '2026-08-27T03:00:00.0000000Z'
        } $report.Scripts[0] $syntheticTaskEvidence $syntheticFailureEvent)
        Assert-That ($observedEvidence.Count -eq 1) 'A matching Task Scheduler event maps to one script evidence row.'
        Assert-That ($observedEvidence[0].Outcome -eq 'Failed') 'A matching non-zero action result maps to a failure.'
        Assert-That ($observedEvidence[0].Attribution -eq 'ExactTaskAction') 'A single matching task action has exact attribution.'
        Assert-That ($observedEvidence[0].EvidenceKey.Length -eq 64) 'Observed evidence has a stable deduplication key.'

        $liveEvidenceBundlePath = Join-Path $temporaryRoot 'Live Evidence Bundle'
        $liveEvidenceReport = Invoke-At0mFlowScriptAudit `
            -ComputerName 'localhost' `
            -SearchPath $sourceRoot `
            -ExcludePath $excludedRoot `
            -OutputPath $liveEvidenceBundlePath
        $liveEvidenceSummary = Get-Content `
            -LiteralPath (Join-Path $liveEvidenceBundlePath 'manifests/summary.json') `
            -Raw | ConvertFrom-Json
        $liveStatus = @($liveEvidenceSummary.TaskEventLogStatusByComputer.PSObject.Properties.Value)[0]
        Assert-That ($liveStatus -in @('Available', 'Disabled', 'Unavailable', 'QueryFailed')) 'The local Task Scheduler event-log state is explicit.'
        Assert-That ($liveEvidenceReport.ExecutionEvidence.Count -ge 1) 'Live task discovery still gives every collected script an evidence status.'

        $unchangedReport = Invoke-At0mFlowScriptAudit `
            -ComputerName 'localhost' `
            -SearchPath $sourceRoot `
            -ExcludePath $excludedRoot `
            -SkipScheduledTasks `
            -OutputPath $bundlePath `
            -Force
        Assert-That ($unchangedReport.Scripts[0].CollectionChange -eq 'Unchanged') 'An identical recurring collection is unchanged.'
        Assert-That ($unchangedReport.Scripts[0].PreviousCollectedSHA256 -eq $sourceHash) 'The previous collected hash is retained.'
        Assert-That ($unchangedReport.Scripts[0].CollectedSHA256 -eq $sourceHash) 'The verified collected hash is retained.'

        Add-Content -LiteralPath $sourcePath -Value "Write-Output 'Synthetic revision'"
        $modifiedReport = Invoke-At0mFlowScriptAudit `
            -ComputerName 'localhost' `
            -SearchPath $sourceRoot `
            -ExcludePath $excludedRoot `
            -SkipScheduledTasks `
            -OutputPath $bundlePath `
            -Force
        Assert-That ($modifiedReport.Scripts[0].CollectionChange -eq 'Modified') 'A changed source records a modified copy.'
        Assert-That ($modifiedReport.Scripts[0].PreviousCollectedSHA256 -eq $sourceHash) 'A modification records the previous copy hash.'
        Assert-That ($modifiedReport.Scripts[0].CollectedSHA256 -eq $modifiedReport.Scripts[0].SHA256) 'A modified copy is hash verified.'

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
        Assert-That ($jsonReport.GitSyncStatus -eq 'NotRequested') 'JSON output reports that Git sync was not requested.'
        Assert-That ($jsonText -notmatch 'PowerShell clarity\.') 'JSON output does not include console branding.'

        if ($null -ne (Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            $gitRemotePath = Join-Path $temporaryRoot 'Synthetic Remote.git'
            $gitWorkingPath = Join-Path $temporaryRoot 'Synthetic Working'
            New-Item -ItemType Directory -Path $gitWorkingPath -Force | Out-Null
            & git init --bare $gitRemotePath | Out-Null
            & git -C $gitWorkingPath init | Out-Null
            & git -C $gitWorkingPath config user.name 'Synthetic Test'
            & git -C $gitWorkingPath config user.email 'test@example.com'
            'Synthetic repository fixture.' | Set-Content -LiteralPath (Join-Path $gitWorkingPath 'NOTICE.txt') -Encoding UTF8
            & git -C $gitWorkingPath add NOTICE.txt
            & git -C $gitWorkingPath commit -m 'Initial synthetic commit' | Out-Null
            & git -C $gitWorkingPath remote add origin $gitRemotePath
            & git -C $gitWorkingPath push -u origin HEAD | Out-Null

            $gitReport = Invoke-At0mFlowScriptAudit `
                -ComputerName 'localhost' `
                -SearchPath $sourceRoot `
                -ExcludePath $excludedRoot `
                -SkipScheduledTasks `
                -OutputPath $gitWorkingPath `
                -Force `
                -GitSync
            Assert-That ($gitReport.GitSyncStatus -eq 'Pushed') 'An approved existing Git working tree is committed and pushed.'
            Assert-That (-not [string]::IsNullOrWhiteSpace($gitReport.GitCommit)) 'The pushed commit identifier is returned.'
            $gitInventory = @(Import-Csv -LiteralPath (Join-Path $gitWorkingPath 'manifests/script-inventory.csv'))
            Assert-That ($gitInventory[0].SourcePhysicalPath -eq $sourcePath) 'The Git inventory records the physical source path.'
            Assert-That (Test-Path -LiteralPath $gitInventory[0].CollectedCopyPath -PathType Leaf) 'The Git inventory records the existing collected copy.'
            Assert-That ($gitInventory[0].RepositoryRelativePath -like 'scripts/*/Synthetic-NightlyReport.ps1') 'The stable Git-relative copy path is recorded.'

            'This staged file must remain outside the collector commit.' |
                Set-Content -LiteralPath (Join-Path $gitWorkingPath 'UNRELATED.txt') -Encoding UTF8
            & git -C $gitWorkingPath add UNRELATED.txt
            Add-Content -LiteralPath $sourcePath -Value "Write-Output 'Second synthetic revision'"
            $secondGitReport = Invoke-At0mFlowScriptAudit `
                -ComputerName 'localhost' `
                -SearchPath $sourceRoot `
                -ExcludePath $excludedRoot `
                -SkipScheduledTasks `
                -OutputPath $gitWorkingPath `
                -Force `
                -GitSync
            Assert-That ($secondGitReport.GitSyncStatus -eq 'Pushed') 'A later source change is committed and pushed.'
            Assert-That ($secondGitReport.Scripts[0].CollectionChange -eq 'Modified') 'The recurring Git copy identifies a modified script.'
            $stagedNames = @(& git -C $gitWorkingPath diff --cached --name-only)
            Assert-That ($stagedNames -contains 'UNRELATED.txt') 'Unrelated staged work remains staged and outside the collector commit.'
            $remoteCommitCount = [int] (& git --git-dir=$gitRemotePath rev-list --count --all)
            Assert-That ($remoteCommitCount -eq 3) 'The private remote receives only the initial and two collector commits.'
        }
        else {
            Write-Host 'SKIP: Git sync integration tests require Git.' -ForegroundColor Yellow
        }

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
