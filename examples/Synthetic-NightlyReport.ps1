<#
Synthetic fixture for documentation only.
#>
# Author: Example Automation Team

[CmdletBinding()]
param(
    [datetime] $ReportDate = (Get-Date)
)

[pscustomobject] @{
    ReportDate = $ReportDate.Date
    Status     = 'Synthetic example only'
}
