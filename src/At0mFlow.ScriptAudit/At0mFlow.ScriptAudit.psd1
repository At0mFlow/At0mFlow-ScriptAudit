@{
    RootModule        = 'At0mFlow.ScriptAudit.psm1'
    ModuleVersion     = '1.1.1'
    GUID              = 'd921fc68-4eb8-4b52-a036-7589f420df49'
    Author            = 'At0mFlow'
    CompanyName       = 'At0mFlow'
    Copyright         = 'Copyright (c) 2026 At0mFlow. Licensed under the MIT License.'
    Description       = 'Collects custom PowerShell scripts and their Windows scheduled-task context into a local audit bundle.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'ConvertTo-At0mFlowCentralPath'
        'Get-At0mFlowTaskScriptReference'
        'Invoke-At0mFlowScriptAudit'
        'Write-At0mFlowScriptAuditReport'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags = @(
                'PowerShell'
                'Windows'
                'ScriptAudit'
                'Inventory'
                'ScheduledTasks'
                'SCCM'
                'WinRM'
                'Migration'
                'PSEdition_Desktop'
                'PSEdition_Core'
            )
            LicenseUri = 'https://github.com/At0mFlow/At0mFlow-ScriptAudit/blob/main/LICENSE'
            ProjectUri = 'https://github.com/At0mFlow/At0mFlow-ScriptAudit'
        }
    }
}
