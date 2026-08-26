<#
.SYNOPSIS
Collects custom PowerShell scripts and Windows scheduled-task context into one audit bundle.

.EXAMPLE
./src/Invoke-At0mFlowScriptAudit.ps1 -SearchPath C:\Scripts

.EXAMPLE
./src/Invoke-At0mFlowScriptAudit.ps1 -ComputerName SERVER01, SERVER02 -ScanFixedDrives

.EXAMPLE
./src/Invoke-At0mFlowScriptAudit.ps1 -ScanFixedDrives -Quiet -FailOnCollectionError
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]] $ComputerName = @($env:COMPUTERNAME),

    [string[]] $SearchPath,

    [ValidateNotNullOrEmpty()]
    [string] $OutputPath = (Join-Path (Get-Location) ('At0mFlow-ScriptAudit-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [Management.Automation.PSCredential] $Credential,

    [switch] $ScanFixedDrives,

    [switch] $SkipScheduledTasks,

    [switch] $IncludeMicrosoftTaskFolder,

    [switch] $IncludeDefaultLocations,

    [string[]] $ExcludePath,

    [ValidateRange(1, 1024)]
    [int] $MaxFileSizeMB = 25,

    [switch] $InventoryOnly,

    [switch] $Force,

    [ValidateSet('Console', 'Object', 'Json')]
    [string] $Format = 'Console',

    [switch] $Quiet,

    [switch] $FailOnCollectionError
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'At0mFlow.ScriptAudit/At0mFlow.ScriptAudit.psd1'

try {
    Import-Module $modulePath -Force

    $auditParameters = @{
        ComputerName               = $ComputerName
        OutputPath                 = $OutputPath
        ScanFixedDrives            = $ScanFixedDrives
        SkipScheduledTasks         = $SkipScheduledTasks
        IncludeMicrosoftTaskFolder = $IncludeMicrosoftTaskFolder
        IncludeDefaultLocations    = $IncludeDefaultLocations
        MaxFileSizeMB              = $MaxFileSizeMB
        InventoryOnly              = $InventoryOnly
        Force                      = $Force
    }
    if (@($SearchPath).Count -gt 0) {
        $auditParameters.SearchPath = $SearchPath
    }
    if (@($ExcludePath).Count -gt 0) {
        $auditParameters.ExcludePath = $ExcludePath
    }
    if ($null -ne $Credential) {
        $auditParameters.Credential = $Credential
    }

    $report = Invoke-At0mFlowScriptAudit @auditParameters

    if (-not $Quiet.IsPresent) {
        switch ($Format) {
            'Console' {
                Write-At0mFlowScriptAuditReport -Report $report
            }
            'Object' {
                $report
            }
            'Json' {
                $report |
                    Select-Object StartedAtUtc, CompletedAtUtc, OutputPath,
                        ComputerCount, ScriptCount, CopiedCount,
                        ScheduledTaskCount, ErrorCount, HasErrors, InventoryOnly |
                    ConvertTo-Json -Depth 4
            }
        }
    }

    if ($FailOnCollectionError.IsPresent -and $report.HasErrors) {
        exit 1
    }

    exit 0
}
catch {
    Write-Error $_
    exit 2
}
