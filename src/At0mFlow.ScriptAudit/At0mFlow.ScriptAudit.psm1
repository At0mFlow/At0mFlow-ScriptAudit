Set-StrictMode -Version 2.0

function Get-At0mFlowSafePathSegment {
    param(
        [AllowEmptyString()]
        [string] $Value
    )

    $safeValue = $Value
    foreach ($character in [IO.Path]::GetInvalidFileNameChars()) {
        $safeValue = $safeValue.Replace([string] $character, '_')
    }

    $safeValue = $safeValue.Replace(':', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safeValue) -or ($safeValue -in @('.', '..'))) {
        return '_'
    }

    return $safeValue
}

function ConvertTo-At0mFlowCentralPath {
    <#
    .SYNOPSIS
    Converts a Windows source path into a safe, computer-scoped bundle path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OriginalPath
    )

    $computerSegment = Get-At0mFlowSafePathSegment -Value $ComputerName
    $normalisedPath = $OriginalPath.Trim().Trim('"').Replace('/', '\')
    $segments = New-Object 'System.Collections.Generic.List[string]'
    $segments.Add('scripts')
    $segments.Add($computerSegment)

    if ($normalisedPath -match '^(?<drive>[A-Za-z]):\\(?<rest>.*)$') {
        $segments.Add($Matches.drive.ToUpperInvariant())
        $remainingPath = $Matches.rest
    }
    elseif ($normalisedPath -match '^\\\\(?<server>[^\\]+)\\(?<share>[^\\]+)\\?(?<rest>.*)$') {
        $segments.Add('UNC')
        $segments.Add((Get-At0mFlowSafePathSegment -Value $Matches.server))
        $segments.Add((Get-At0mFlowSafePathSegment -Value $Matches.share))
        $remainingPath = $Matches.rest
    }
    else {
        $segments.Add('OTHER')
        $remainingPath = $normalisedPath.TrimStart('\')
    }

    foreach ($segment in @($remainingPath -split '\\')) {
        if (-not [string]::IsNullOrWhiteSpace($segment)) {
            $segments.Add((Get-At0mFlowSafePathSegment -Value $segment))
        }
    }

    return ($segments.ToArray() -join '/')
}

function Get-At0mFlowTaskScriptReference {
    <#
    .SYNOPSIS
    Extracts PowerShell script paths from a scheduled-task action.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string] $Execute,

        [AllowEmptyString()]
        [string] $Arguments,

        [AllowEmptyString()]
        [string] $WorkingDirectory
    )

    $references = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    $candidateText = [Environment]::ExpandEnvironmentVariables(('{0} {1}' -f $Execute, $Arguments))
    $pattern = '(?i)(?:"(?<double>[^"\r\n]+\.ps1)"|''(?<single>[^''\r\n]+\.ps1)''|(?<bare>(?:[A-Z]:[\\/]|\\\\|\.{1,2}[\\/])[^\s"''|&<>]+\.ps1))'

    foreach ($match in [regex]::Matches($candidateText, $pattern)) {
        $reference = if ($match.Groups['double'].Success) {
            $match.Groups['double'].Value
        }
        elseif ($match.Groups['single'].Success) {
            $match.Groups['single'].Value
        }
        else {
            $match.Groups['bare'].Value
        }

        $reference = [Environment]::ExpandEnvironmentVariables($reference.Trim())
        if (($reference -match '^\.{1,2}[\\/]') -and
            -not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $basePath = [Environment]::ExpandEnvironmentVariables($WorkingDirectory.Trim().Trim('"'))
            $combined = $basePath.TrimEnd('\', '/') + '\' + $reference.Replace('/', '\')

            $prefix = ''
            $pathToResolve = $combined
            if ($combined -match '^(?<drive>[A-Za-z]:)\\(?<rest>.*)$') {
                $prefix = $Matches.drive + '\'
                $pathToResolve = $Matches.rest
            }
            elseif ($combined -match '^(?<unc>\\\\[^\\]+\\[^\\]+)\\?(?<rest>.*)$') {
                $prefix = $Matches.unc + '\'
                $pathToResolve = $Matches.rest
            }

            $resolvedSegments = New-Object 'System.Collections.Generic.List[string]'
            foreach ($pathSegment in @($pathToResolve -split '\\')) {
                if ([string]::IsNullOrWhiteSpace($pathSegment) -or ($pathSegment -eq '.')) {
                    continue
                }
                if ($pathSegment -eq '..') {
                    if ($resolvedSegments.Count -gt 0) {
                        $resolvedSegments.RemoveAt($resolvedSegments.Count - 1)
                    }
                    continue
                }
                $resolvedSegments.Add($pathSegment)
            }
            $reference = $prefix + ($resolvedSegments.ToArray() -join '\')
        }

        $key = $reference.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $references.Add($reference)
        }
    }

    return $references.ToArray()
}

function Test-At0mFlowLocalComputer {
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName
    )

    $localNames = @(
        '.',
        'localhost',
        '127.0.0.1',
        '::1',
        $env:COMPUTERNAME
    )

    return $localNames -contains $ComputerName
}

function Invoke-At0mFlowGitCommand {
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [int[]] $AcceptedExitCode = @(0)
    )

    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $gitCommand) {
        throw 'Git is required for -GitSync but was not found on PATH.'
    }

    $previousPromptSetting = $env:GIT_TERMINAL_PROMPT
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $env:GIT_TERMINAL_PROMPT = '0'
        $ErrorActionPreference = 'Continue'
        $commandOutput = @(
            & $gitCommand.Source -C $WorkingDirectory -c core.longpaths=true @ArgumentList 2>&1
        )
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        [Environment]::SetEnvironmentVariable(
            'GIT_TERMINAL_PROMPT',
            $previousPromptSetting,
            [EnvironmentVariableTarget]::Process
        )
    }

    if ($AcceptedExitCode -notcontains $exitCode) {
        $readableOutput = ($commandOutput | ForEach-Object { [string] $_ }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($readableOutput)) {
            $readableOutput = 'Git returned no diagnostic output.'
        }
        throw "Git command failed with exit code $exitCode`: git $($ArgumentList -join ' ')`n$readableOutput"
    }

    [pscustomobject] @{
        ExitCode = $exitCode
        Output   = (($commandOutput | ForEach-Object { [string] $_ }) -join [Environment]::NewLine).Trim()
    }
}

function Get-At0mFlowGitContext {
    param(
        [Parameter(Mandatory)]
        [string] $OutputPath,

        [switch] $Required
    )

    if ($null -eq (Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        if ($Required.IsPresent) {
            throw 'Git is required for -GitSync but was not found on PATH.'
        }
        return $null
    }

    try {
        $rootResult = Invoke-At0mFlowGitCommand `
            -WorkingDirectory $OutputPath `
            -ArgumentList @('rev-parse', '--show-toplevel')
    }
    catch {
        if ($Required.IsPresent) {
            throw "-GitSync requires OutputPath to be inside an existing Git working tree. $($_.Exception.Message)"
        }
        return $null
    }

    $gitRoot = [IO.Path]::GetFullPath($rootResult.Output).TrimEnd('\', '/')
    $resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath).TrimEnd('\', '/')
    $rootPrefix = $gitRoot + [IO.Path]::DirectorySeparatorChar
    if (($resolvedOutputPath -ne $gitRoot) -and
        -not $resolvedOutputPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The resolved output path is outside the Git working tree.'
    }

    $pathToCheck = Get-Item -LiteralPath $resolvedOutputPath -Force -ErrorAction Stop
    while ($null -ne $pathToCheck) {
        if ($pathToCheck.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "-GitSync does not allow a reparse point in the output path: $($pathToCheck.FullName)"
        }
        if ($pathToCheck.FullName.TrimEnd('\', '/') -eq $gitRoot) {
            break
        }
        $pathToCheck = $pathToCheck.Parent
    }

    $outputRelativePath = if ($resolvedOutputPath -eq $gitRoot) {
        '.'
    }
    else {
        $resolvedOutputPath.Substring($rootPrefix.Length).Replace('\', '/')
    }
    $pathPrefix = if ($outputRelativePath -eq '.') { '' } else { $outputRelativePath + '/' }

    [pscustomobject] @{
        RootPath           = $gitRoot
        OutputRelativePath = $outputRelativePath
        Pathspecs          = @(
            $pathPrefix + 'scripts'
            $pathPrefix + 'manifests'
            $pathPrefix + 'README.txt'
        )
    }
}

function Invoke-At0mFlowGitSync {
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CommitMessage
    )

    $pathspecs = @($Context.Pathspecs)
    Invoke-At0mFlowGitCommand `
        -WorkingDirectory $Context.RootPath `
        -ArgumentList (@('add', '-A', '--') + $pathspecs) | Out-Null

    $diffResult = Invoke-At0mFlowGitCommand `
        -WorkingDirectory $Context.RootPath `
        -ArgumentList (@('diff', '--cached', '--quiet', '--') + $pathspecs) `
        -AcceptedExitCode @(0, 1)
    if ($diffResult.ExitCode -eq 0) {
        return [pscustomobject] @{
            Status = 'NoChanges'
            Commit = ''
        }
    }

    $datedMessage = '{0} ({1})' -f $CommitMessage.Trim(), ([DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
    Invoke-At0mFlowGitCommand `
        -WorkingDirectory $Context.RootPath `
        -ArgumentList (@('commit', '--only', '-m', $datedMessage, '--') + $pathspecs) | Out-Null
    $commitResult = Invoke-At0mFlowGitCommand `
        -WorkingDirectory $Context.RootPath `
        -ArgumentList @('rev-parse', 'HEAD')
    Invoke-At0mFlowGitCommand `
        -WorkingDirectory $Context.RootPath `
        -ArgumentList @('push') | Out-Null

    [pscustomobject] @{
        Status = 'Pushed'
        Commit = $commitResult.Output
    }
}

function Get-At0mFlowTaskEventOutcome {
    param(
        [Parameter(Mandatory)]
        [int] $EventId,

        [AllowEmptyString()]
        [string] $ResultCode
    )

    if ($EventId -in @(101, 104, 311)) {
        return 'Failed'
    }
    if ($EventId -ne 201) {
        return 'Unknown'
    }

    $normalisedResult = $ResultCode.Trim()
    if ([string]::IsNullOrWhiteSpace($normalisedResult)) {
        return 'Unknown'
    }

    $numericResult = [uint64] 0
    $signedResult = [int64] 0
    $parsed = if ($normalisedResult.StartsWith('0x', [StringComparison]::OrdinalIgnoreCase)) {
        [uint64]::TryParse(
            $normalisedResult.Substring(2),
            [Globalization.NumberStyles]::HexNumber,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref] $numericResult
        )
    }
    else {
        if ([uint64]::TryParse($normalisedResult, [ref] $numericResult)) {
            $true
        }
        elseif ([int64]::TryParse($normalisedResult, [ref] $signedResult)) {
            if ($signedResult -lt 0) {
                return 'Failed'
            }
            $numericResult = [uint64] $signedResult
            $true
        }
        else {
            $false
        }
    }
    if (-not $parsed) {
        return 'Unknown'
    }

    if ($numericResult -eq 0) { return 'Succeeded' }
    if (($numericResult -ge 0x00041300) -and ($numericResult -le 0x00041308)) {
        return 'SchedulerStatus'
    }
    return 'Failed'
}

function Get-At0mFlowEvidenceKey {
    param(
        [Parameter(Mandatory)]
        [string[]] $Value
    )

    $text = $Value -join '|'
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}

function ConvertTo-At0mFlowExecutionEvidence {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Scripts,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Tasks,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $TaskEvents,

        [Parameter(Mandatory)]
        [string] $EventLogStatus,

        [Parameter(Mandatory)]
        [string] $LookbackStartUtc,

        [Parameter(Mandatory)]
        [string] $LookbackEndUtc
    )

    $rows = New-Object 'System.Collections.Generic.List[object]'
    $evidenceLookbackStartUtc = $LookbackStartUtc
    $evidenceLookbackEndUtc = $LookbackEndUtc

    function Add-EvidenceRow {
        param(
            [psobject] $Script,
            [string] $EvidenceStatus,
            [string] $Outcome,
            [string] $Attribution,
            [psobject] $Task,
            [psobject] $TaskEvent
        )

        $eventTime = if ($null -ne $TaskEvent) { [string] $TaskEvent.EventTimeUtc } else { '' }
        $eventId = if ($null -ne $TaskEvent) { [string] $TaskEvent.EventId } else { '' }
        $eventRecordId = if ($null -ne $TaskEvent) { [string] $TaskEvent.EventRecordId } else { '' }
        $resultCode = if ($null -ne $TaskEvent) { [string] $TaskEvent.ResultCode } else { '' }
        $action = if ($null -ne $TaskEvent) { [string] $TaskEvent.ActionName } elseif ($null -ne $Task) { [string] $Task.ActionExecute } else { '' }
        $taskName = if ($null -ne $Task) { [string] $Task.TaskName } elseif ($null -ne $TaskEvent) { [string] $TaskEvent.TaskName } else { '' }
        $taskPath = if ($null -ne $Task) { [string] $Task.TaskPath } else { '' }
        $isFailure = if ($Outcome -eq 'Failed') { 'True' } elseif ($Outcome -eq 'Succeeded') { 'False' } else { '' }
        $evidenceKey = if ($EvidenceStatus -eq 'Observed') {
            Get-At0mFlowEvidenceKey -Value @(
                [string] $Script.ComputerName,
                [string] $Script.CentralRelativePath,
                $eventRecordId,
                $eventId,
                $taskPath,
                $taskName,
                $resultCode
            )
        }
        else { '' }

        $rows.Add([pscustomobject] @{
            ComputerName          = $Script.ComputerName
            SourcePhysicalPath    = $Script.SourcePhysicalPath
            CollectedCopyPath     = $Script.CollectedCopyPath
            RepositoryRelativePath = $Script.RepositoryRelativePath
            CentralRelativePath   = $Script.CentralRelativePath
            EvidenceStatus        = $EvidenceStatus
            Outcome               = $Outcome
            IsFailure             = $isFailure
            Attribution           = $Attribution
            EventTimeUtc          = $eventTime
            EventId               = $eventId
            EventRecordId         = $eventRecordId
            TaskName              = $taskName
            TaskPath              = $taskPath
            Action                = $action
            ResultCode            = $resultCode
            EvidenceKey           = $evidenceKey
            EvidenceSource        = 'Microsoft-Windows-TaskScheduler/Operational'
            LookbackStartUtc      = $evidenceLookbackStartUtc
            LookbackEndUtc        = $evidenceLookbackEndUtc
        })
    }

    foreach ($script in $Scripts) {
        $relatedTasks = @(
            foreach ($task in $Tasks) {
                $references = @(
                    ([string] $task.IncludedScriptReferences) -split ';\s*' |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                )
                if (@($references | Where-Object {
                    $_.Equals([string] $script.SourcePhysicalPath, [StringComparison]::OrdinalIgnoreCase)
                }).Count -gt 0) {
                    $task
                }
            }
        )

        if ($relatedTasks.Count -eq 0) {
            Add-EvidenceRow -Script $script -EvidenceStatus 'NoScheduledTaskReference' `
                -Outcome 'Unknown' -Attribution 'None' -Task $null -TaskEvent $null
            continue
        }
        if ($EventLogStatus -ne 'Available') {
            Add-EvidenceRow -Script $script -EvidenceStatus 'EventLogUnavailable' `
                -Outcome 'Unknown' -Attribution 'None' -Task $relatedTasks[0] -TaskEvent $null
            continue
        }

        $observedKeys = @{}
        $observationCount = 0
        foreach ($task in $relatedTasks) {
            $fullTaskName = '{0}{1}' -f $task.TaskPath, $task.TaskName
            $matchingEvents = @($TaskEvents | Where-Object {
                ([string] $_.TaskName).Equals($fullTaskName, [StringComparison]::OrdinalIgnoreCase)
            })
            foreach ($taskEventRecord in $matchingEvents) {
                $dedupeKey = '{0}|{1}' -f $taskEventRecord.EventRecordId, $script.CentralRelativePath
                if ($observedKeys.ContainsKey($dedupeKey)) {
                    continue
                }
                $observedKeys[$dedupeKey] = $true

                $attribution = 'TaskLevel'
                if ([int] $taskEventRecord.EventId -eq 201) {
                    $candidateActions = @($relatedTasks | Where-Object {
                        ('{0}{1}' -f $_.TaskPath, $_.TaskName).Equals($fullTaskName, [StringComparison]::OrdinalIgnoreCase) -and
                        -not [string]::IsNullOrWhiteSpace([string] $taskEventRecord.ActionName) -and
                        ([string] $_.ActionExecute).Trim().Trim('"').Equals(
                            ([string] $taskEventRecord.ActionName).Trim().Trim('"'),
                            [StringComparison]::OrdinalIgnoreCase
                        )
                    })
                    $attribution = if ($candidateActions.Count -eq 1) {
                        'ExactTaskAction'
                    }
                    else {
                        'TaskActionAmbiguous'
                    }
                }

                $outcome = Get-At0mFlowTaskEventOutcome `
                    -EventId ([int] $taskEventRecord.EventId) `
                    -ResultCode ([string] $taskEventRecord.ResultCode)
                Add-EvidenceRow -Script $script -EvidenceStatus 'Observed' `
                    -Outcome $outcome -Attribution $attribution -Task $task -TaskEvent $taskEventRecord
                $observationCount++
            }
        }
        if ($observationCount -eq 0) {
            Add-EvidenceRow -Script $script -EvidenceStatus 'NoEventInLookback' `
                -Outcome 'Unknown' -Attribution 'None' -Task $relatedTasks[0] -TaskEvent $null
        }
    }

    return $rows.ToArray()
}

function Export-At0mFlowCsv {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $InputObject,

        [Parameter(Mandatory)]
        [string[]] $Property,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if ($InputObject.Count -eq 0) {
        $header = ($Property | ForEach-Object { '"{0}"' -f $_.Replace('"', '""') }) -join ','
        $header | Set-Content -LiteralPath $Path -Encoding UTF8
        return
    }

    $InputObject |
        Select-Object -Property $Property |
        Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
}

function Write-At0mFlowBundleTree {
    param(
        [Parameter(Mandatory)]
        [string] $ScriptsPath,

        [Parameter(Mandatory)]
        [string] $TreePath
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('scripts/')
    if (Test-Path -LiteralPath $ScriptsPath -PathType Container) {
        $items = @(
            Get-ChildItem -LiteralPath $ScriptsPath -Recurse -Force |
                Sort-Object FullName
        )
        foreach ($item in $items) {
            $relativePath = $item.FullName.Substring($ScriptsPath.Length).TrimStart('\', '/')
            $depth = @($relativePath -split '[\\/]').Count
            $indent = '  ' * $depth
            $suffix = if ($item.PSIsContainer) { '/' } else { '' }
            $lines.Add($indent + $item.Name + $suffix)
        }
    }

    $lines.ToArray() | Set-Content -LiteralPath $TreePath -Encoding UTF8
}

function Write-At0mFlowWordmark {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'The wordmark is intended for interactive console output.'
    )]
    [CmdletBinding()]
    param()

    $logoLines = @(
        '       #####> ########> ######> ###>   ###>#######>##>      ######> ##>    ##>'
        '      ##<--##>[--##<--]##<-####>####> ####|##<----]##|     ##<---##>##|    ##|'
        '      #######|   ##|   ##|##<##|##<####<##|#####>  ##|     ##|   ##|##| #> ##|'
        '      ##<--##|   ##|   ####<]##|##|[##<]##|##<--]  ##|     ##|   ##|##|###>##|'
        '      ##|  ##|   ##|   [######<]##| [-] ##|##|     #######>[######<][###<###<]'
        '      [-]  [-]   [-]    [-----] [-]     [-][-]     [------] [-----]  [--][--]'
    )
    $logoGlyphs = [ordered] @{
        '#' = [char] 0x2588
        '<' = [char] 0x2554
        '>' = [char] 0x2557
        '[' = [char] 0x255A
        ']' = [char] 0x255D
        '-' = [char] 0x2550
        '|' = [char] 0x2551
    }

    Write-Host '========================================================================' -ForegroundColor DarkGray
    Write-Host ''
    foreach ($logoLine in $logoLines) {
        $renderedLogoLine = $logoLine
        foreach ($placeholder in $logoGlyphs.Keys) {
            $renderedLogoLine = $renderedLogoLine.Replace(
                $placeholder,
                [string] $logoGlyphs[$placeholder]
            )
        }
        Write-Host $renderedLogoLine -ForegroundColor Cyan
    }
    Write-Host ''
    Write-Host '                     PowerShell clarity.' -ForegroundColor White
    Write-Host '                      Orbit-level control.' -ForegroundColor White
    Write-Host ''
    Write-Host '                   ANALYSE | CLEAN | MIGRATE | MONITOR' -ForegroundColor Green
    Write-Host ''
    Write-Host '                         https://at0mflow.com' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '========================================================================' -ForegroundColor DarkGray
}

function Invoke-At0mFlowScriptAudit {
    <#
    .SYNOPSIS
    Collects custom PowerShell scripts and scheduled-task context from Windows computers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ComputerName = @($env:COMPUTERNAME),

        [string[]] $SearchPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OutputPath,

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

        [switch] $GitSync,

        [ValidateNotNullOrEmpty()]
        [string] $GitCommitMessage = 'At0mFlow Script Audit refresh'
    )

    if ($env:OS -ne 'Windows_NT') {
        throw 'At0mFlow Script Audit must run on Windows.'
    }
    if ($GitSync.IsPresent -and $InventoryOnly.IsPresent) {
        throw '-GitSync cannot be combined with -InventoryOnly because there are no copied scripts to synchronise.'
    }

    $startedAtUtc = [DateTimeOffset]::UtcNow
    $resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
    if (Test-Path -LiteralPath $resolvedOutputPath) {
        $existingItems = @(Get-ChildItem -LiteralPath $resolvedOutputPath -Force -ErrorAction Stop)
        if (($existingItems.Count -gt 0) -and -not $Force.IsPresent) {
            throw "OutputPath is not empty. Choose a new path or use -Force: $resolvedOutputPath"
        }
    }
    else {
        New-Item -ItemType Directory -Path $resolvedOutputPath -Force | Out-Null
    }

    $scriptsPath = Join-Path $resolvedOutputPath 'scripts'
    $manifestsPath = Join-Path $resolvedOutputPath 'manifests'
    New-Item -ItemType Directory -Path $scriptsPath -Force | Out-Null
    New-Item -ItemType Directory -Path $manifestsPath -Force | Out-Null
    $gitContext = Get-At0mFlowGitContext -OutputPath $resolvedOutputPath -Required:$GitSync.IsPresent

    $scriptRows = New-Object 'System.Collections.Generic.List[object]'
    $taskRows = New-Object 'System.Collections.Generic.List[object]'
    $taskEventRows = New-Object 'System.Collections.Generic.List[object]'
    $errorRows = New-Object 'System.Collections.Generic.List[object]'
    $searchRootsByComputer = [ordered] @{}
    $taskEventLogStatusByComputer = [ordered] @{}
    $eventLookbackByComputer = [ordered] @{}
    $parserDefinition = ${function:Get-At0mFlowTaskScriptReference}.ToString()
    $maximumBytes = [int64] $MaxFileSizeMB * 1MB

    $discoveryScript = {
        param(
            [string[]] $RequestedSearchPath,
            [bool] $ScanAllFixedDrives,
            [bool] $DoNotReadScheduledTasks,
            [bool] $ReadMicrosoftTaskFolder,
            [bool] $ReadDefaultLocations,
            [string[]] $RequestedExcludePath,
            [string] $CollectorOutputPath,
            [int64] $MaximumFileBytes,
            [string] $TaskParserDefinition
        )

        Set-StrictMode -Version 2.0
        Set-Item -LiteralPath function:Get-At0mFlowTaskScriptReference -Value ([scriptblock]::Create($TaskParserDefinition))

        $computer = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
            [Net.Dns]::GetHostName()
        }
        else {
            $env:COMPUTERNAME
        }
        $errors = New-Object 'System.Collections.Generic.List[object]'
        $tasks = New-Object 'System.Collections.Generic.List[object]'
        $taskEvents = New-Object 'System.Collections.Generic.List[object]'
        $scripts = New-Object 'System.Collections.Generic.List[object]'
        $eventLookbackEndUtc = [DateTimeOffset]::UtcNow
        $eventLookbackStartUtc = $eventLookbackEndUtc.AddHours(-1)
        $taskEventLogStatus = if ($DoNotReadScheduledTasks) { 'Skipped' } else { 'Unavailable' }
        $candidates = @{}
        $state = @{ SuppressedErrors = 0 }
        $maximumRecordedErrors = 200

        function Add-DiscoveryError {
            param(
                [string] $Stage,
                [string] $Target,
                [string] $Message
            )

            if ($errors.Count -lt $maximumRecordedErrors) {
                $errors.Add([pscustomobject] @{
                    ComputerName = $computer
                    Stage        = $Stage
                    Target       = $Target
                    Message      = $Message
                })
            }
            else {
                $state.SuppressedErrors++
            }
        }

        $fixedDriveRoots = @(
            Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                Where-Object { $_.Root -match '^[A-Za-z]:\\$' } |
                Select-Object -ExpandProperty Root -Unique
        )

        $defaultExclusions = New-Object 'System.Collections.Generic.List[string]'
        if (-not $ReadDefaultLocations) {
            foreach ($defaultPath in @(
                $env:windir,
                $env:ProgramFiles,
                ${env:ProgramFiles(x86)},
                (Join-Path $env:ProgramData 'Microsoft'),
                (Join-Path $env:ProgramData 'Package Cache')
            )) {
                if (-not [string]::IsNullOrWhiteSpace($defaultPath)) {
                    $defaultExclusions.Add([Environment]::ExpandEnvironmentVariables($defaultPath))
                }
            }
        }
        foreach ($driveRoot in $fixedDriveRoots) {
            $defaultExclusions.Add((Join-Path $driveRoot '$Recycle.Bin'))
            $defaultExclusions.Add((Join-Path $driveRoot 'System Volume Information'))
        }
        if (-not [string]::IsNullOrWhiteSpace($CollectorOutputPath)) {
            $defaultExclusions.Add($CollectorOutputPath)
        }
        foreach ($requestedExclusion in @($RequestedExcludePath)) {
            if (-not [string]::IsNullOrWhiteSpace($requestedExclusion)) {
                $defaultExclusions.Add([Environment]::ExpandEnvironmentVariables($requestedExclusion))
            }
        }

        $normalisedExclusions = @(
            foreach ($exclusion in $defaultExclusions.ToArray()) {
                try {
                    [IO.Path]::GetFullPath($exclusion).TrimEnd('\', '/')
                }
                catch {
                    Add-DiscoveryError -Stage 'Exclusion' -Target $exclusion -Message $_.Exception.Message
                }
            }
        )

        function Test-ExcludedPath {
            param([string] $Path)

            try {
                $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
            }
            catch {
                return $true
            }

            foreach ($exclusion in $normalisedExclusions) {
                if (($fullPath -eq $exclusion) -or
                    $fullPath.StartsWith($exclusion + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    return $true
                }
            }
            return $false
        }

        function Add-ScriptCandidate {
            param(
                [string] $Path,
                [string] $Source,
                [string] $TaskReference
            )

            if ([string]::IsNullOrWhiteSpace($Path)) {
                return
            }
            $expandedPath = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
            if ([IO.Path]::GetExtension($expandedPath) -ne '.ps1') {
                return
            }
            if (Test-ExcludedPath -Path $expandedPath) {
                return
            }

            $key = $expandedPath.ToLowerInvariant()
            if (-not $candidates.ContainsKey($key)) {
                $candidates[$key] = @{
                    Path       = $expandedPath
                    Sources    = New-Object 'System.Collections.Generic.List[string]'
                    TaskNames  = New-Object 'System.Collections.Generic.List[string]'
                }
            }
            if (-not $candidates[$key].Sources.Contains($Source)) {
                $candidates[$key].Sources.Add($Source)
            }
            if (-not [string]::IsNullOrWhiteSpace($TaskReference) -and
                -not $candidates[$key].TaskNames.Contains($TaskReference)) {
                $candidates[$key].TaskNames.Add($TaskReference)
            }
        }

        function Get-TriggerSummary {
            param($Trigger)

            $parts = New-Object 'System.Collections.Generic.List[string]'
            if (($null -ne $Trigger.CimClass) -and
                -not [string]::IsNullOrWhiteSpace($Trigger.CimClass.CimClassName)) {
                $parts.Add($Trigger.CimClass.CimClassName.Replace('MSFT_Task', '').Replace('Trigger', ''))
            }
            foreach ($propertyName in @(
                'StartBoundary', 'EndBoundary', 'DaysInterval', 'WeeksInterval',
                'DaysOfWeek', 'WeeksOfMonth', 'MonthsOfYear', 'UserId',
                'RepetitionInterval', 'RepetitionDuration', 'RandomDelay'
            )) {
                $property = $Trigger.PSObject.Properties[$propertyName]
                if (($null -ne $property) -and ($null -ne $property.Value) -and
                    -not [string]::IsNullOrWhiteSpace([string] $property.Value)) {
                    $parts.Add(('{0}={1}' -f $propertyName, $property.Value))
                }
            }
            return ($parts.ToArray() -join '; ')
        }

        function Get-ConditionSummary {
            param($Settings)

            $parts = New-Object 'System.Collections.Generic.List[string]'
            foreach ($propertyName in @(
                'AllowStartIfOnBatteries', 'DontStopIfGoingOnBatteries',
                'RunOnlyIfIdle', 'RunOnlyIfNetworkAvailable', 'StartWhenAvailable',
                'WakeToRun', 'ExecutionTimeLimit', 'MultipleInstances'
            )) {
                $property = $Settings.PSObject.Properties[$propertyName]
                if (($null -ne $property) -and ($null -ne $property.Value)) {
                    $parts.Add(('{0}={1}' -f $propertyName, $property.Value))
                }
            }
            return ($parts.ToArray() -join '; ')
        }

        if (-not $DoNotReadScheduledTasks) {
            $scheduledTaskCommand = Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue
            if ($null -eq $scheduledTaskCommand) {
                Add-DiscoveryError -Stage 'ScheduledTasks' -Target $computer -Message 'The ScheduledTasks module is not available.'
            }
            else {
                try {
                    $scheduledTasks = @(Get-ScheduledTask -ErrorAction Stop)
                    foreach ($task in $scheduledTasks) {
                        $taskKey = '{0}{1}' -f $task.TaskPath, $task.TaskName
                        try {
                            if (-not $ReadMicrosoftTaskFolder -and
                                ([string] $task.TaskPath).StartsWith('\Microsoft\', [StringComparison]::OrdinalIgnoreCase)) {
                                continue
                            }

                            $triggerSummary = @($task.Triggers | ForEach-Object { Get-TriggerSummary -Trigger $_ }) -join ' | '
                            $conditionSummary = Get-ConditionSummary -Settings $task.Settings
                            $taskInfo = $null
                            try {
                                $taskInfo = Get-ScheduledTaskInfo -InputObject $task -ErrorAction Stop
                            }
                            catch {
                                Add-DiscoveryError -Stage 'ScheduledTaskInfo' -Target $taskKey -Message $_.Exception.Message
                            }

                            $actionIndex = 0
                            foreach ($action in @($task.Actions)) {
                                $actionIndex++
                                $executeProperty = $action.PSObject.Properties['Execute']
                                if ($null -eq $executeProperty) {
                                    continue
                                }
                                $argumentsProperty = $action.PSObject.Properties['Arguments']
                                $workingDirectoryProperty = $action.PSObject.Properties['WorkingDirectory']
                                $execute = [Environment]::ExpandEnvironmentVariables([string] $executeProperty.Value)
                                $arguments = if ($null -ne $argumentsProperty) {
                                    [Environment]::ExpandEnvironmentVariables([string] $argumentsProperty.Value)
                                }
                                else { '' }
                                $workingDirectory = if ($null -ne $workingDirectoryProperty) {
                                    [Environment]::ExpandEnvironmentVariables([string] $workingDirectoryProperty.Value)
                                }
                                else { '' }
                                $references = @(
                                    Get-At0mFlowTaskScriptReference `
                                        -Execute $execute `
                                        -Arguments $arguments `
                                        -WorkingDirectory $workingDirectory
                                )
                                $includedReferences = New-Object 'System.Collections.Generic.List[string]'
                                $excludedReferences = New-Object 'System.Collections.Generic.List[string]'
                                foreach ($reference in $references) {
                                    if (Test-ExcludedPath -Path $reference) {
                                        $excludedReferences.Add($reference)
                                    }
                                    else {
                                        $includedReferences.Add($reference)
                                        Add-ScriptCandidate -Path $reference -Source 'ScheduledTask' -TaskReference $taskKey
                                    }
                                }

                                $executeToken = $execute.Trim().Trim('"')
                                $executeParts = @($executeToken -split '[\\/]')
                                $executableName = $executeParts[$executeParts.Count - 1]
                                $isPowerShellAction = ($executableName -in @('powershell.exe', 'pwsh.exe', 'powershell', 'pwsh')) -or
                                    $execute.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase) -or
                                    ($references.Count -gt 0)
                                if (-not $isPowerShellAction) {
                                    continue
                                }

                                $lastRunUtc = if (($null -ne $taskInfo) -and ($taskInfo.LastRunTime -gt [datetime]::MinValue)) {
                                    $taskInfo.LastRunTime.ToUniversalTime().ToString('o')
                                }
                                else { '' }
                                $nextRunUtc = if (($null -ne $taskInfo) -and ($taskInfo.NextRunTime -gt [datetime]::MinValue)) {
                                    $taskInfo.NextRunTime.ToUniversalTime().ToString('o')
                                }
                                else { '' }

                                $tasks.Add([pscustomobject] @{
                                    ComputerName             = $computer
                                    TaskName                  = $task.TaskName
                                    TaskPath                  = $task.TaskPath
                                    State                     = $task.State
                                    Author                    = $task.Author
                                    Description               = $task.Description
                                    Principal                 = $task.Principal.UserId
                                    RunLevel                  = $task.Principal.RunLevel
                                    LogonType                 = $task.Principal.LogonType
                                    ActionIndex               = $actionIndex
                                    ActionExecute             = $execute
                                    ActionArguments           = $arguments
                                    WorkingDirectory          = $workingDirectory
                                    ScriptReferences          = $references -join '; '
                                    IncludedScriptReferences  = $includedReferences.ToArray() -join '; '
                                    ExcludedScriptReferences  = $excludedReferences.ToArray() -join '; '
                                    Triggers                   = $triggerSummary
                                    Conditions                 = $conditionSummary
                                    LastRunUtc                 = $lastRunUtc
                                    NextRunUtc                 = $nextRunUtc
                                    LastTaskResult             = $(if ($null -ne $taskInfo) { $taskInfo.LastTaskResult } else { $null })
                                })
                            }
                        }
                        catch {
                            Add-DiscoveryError -Stage 'ScheduledTask' -Target $taskKey -Message $_.Exception.Message
                        }
                    }
                }
                catch {
                    Add-DiscoveryError -Stage 'ScheduledTasks' -Target $computer -Message $_.Exception.Message
                }
            }

            try {
                $taskSchedulerLog = Get-WinEvent `
                    -ListLog 'Microsoft-Windows-TaskScheduler/Operational' `
                    -ErrorAction Stop
                if (-not $taskSchedulerLog.IsEnabled) {
                    $taskEventLogStatus = 'Disabled'
                }
                else {
                    $taskEventLogStatus = 'Available'
                    $eventErrors = @()
                    $recentEvents = @(
                        Get-WinEvent -FilterHashtable @{
                            LogName   = 'Microsoft-Windows-TaskScheduler/Operational'
                            Id        = @(101, 104, 201, 311)
                            StartTime = $eventLookbackStartUtc.LocalDateTime
                            EndTime   = $eventLookbackEndUtc.LocalDateTime
                        } -ErrorAction SilentlyContinue -ErrorVariable +eventErrors
                    )
                    if ($eventErrors.Count -gt 0) {
                        $nonEmptyErrors = @($eventErrors | Where-Object {
                            ([string] $_).IndexOf('No events were found', [StringComparison]::OrdinalIgnoreCase) -lt 0
                        })
                        if ($nonEmptyErrors.Count -gt 0) {
                            $taskEventLogStatus = 'QueryFailed'
                        }
                    }

                    foreach ($eventRecord in $recentEvents) {
                        try {
                            [xml] $eventXml = $eventRecord.ToXml()
                            $eventData = @{}
                            foreach ($dataNode in @($eventXml.Event.EventData.Data)) {
                                $dataName = ''
                                if ($null -ne $dataNode.Attributes['Name']) {
                                    $dataName = [string] $dataNode.Attributes['Name'].Value
                                }
                                if (-not [string]::IsNullOrWhiteSpace($dataName)) {
                                    $eventData[$dataName] = [string] $dataNode.InnerText
                                }
                            }
                            $eventTaskName = [string] $eventData['TaskName']
                            if ([string]::IsNullOrWhiteSpace($eventTaskName)) {
                                continue
                            }
                            $resultCode = [string] $eventData['ResultCode']
                            if ([string]::IsNullOrWhiteSpace($resultCode)) {
                                $resultCode = [string] $eventData['ErrorValue']
                            }
                            $actionName = [string] $eventData['ActionName']
                            if ([string]::IsNullOrWhiteSpace($actionName)) {
                                $actionName = [string] $eventData['Action']
                            }
                            $taskEvents.Add([pscustomobject] @{
                                ComputerName  = $computer
                                EventTimeUtc   = $eventRecord.TimeCreated.ToUniversalTime().ToString('o')
                                EventId        = $eventRecord.Id
                                EventRecordId  = $eventRecord.RecordId
                                TaskName       = $eventTaskName
                                ActionName     = $actionName
                                ResultCode     = $resultCode
                            })
                        }
                        catch {
                            Add-DiscoveryError -Stage 'TaskEventParse' -Target ([string] $eventRecord.RecordId) -Message $_.Exception.Message
                        }
                    }
                }
            }
            catch {
                $taskEventLogStatus = 'Unavailable'
            }
        }

        $roots = New-Object 'System.Collections.Generic.List[string]'
        if ($ScanAllFixedDrives) {
            foreach ($driveRoot in $fixedDriveRoots) {
                if (-not $roots.Contains($driveRoot)) {
                    $roots.Add($driveRoot)
                }
            }
        }
        elseif (@($RequestedSearchPath).Count -gt 0) {
            foreach ($requestedRoot in @($RequestedSearchPath)) {
                if (-not [string]::IsNullOrWhiteSpace($requestedRoot)) {
                    $expandedRoot = [Environment]::ExpandEnvironmentVariables($requestedRoot)
                    if (-not $roots.Contains($expandedRoot)) {
                        $roots.Add($expandedRoot)
                    }
                }
            }
        }
        else {
            foreach ($driveRoot in $fixedDriveRoots) {
                foreach ($folderName in @('Scripts', 'Automation', 'PowerShell', 'Ops', 'Admin', 'Tools')) {
                    $commonRoot = Join-Path $driveRoot $folderName
                    if (Test-Path -LiteralPath $commonRoot -PathType Container) {
                        $roots.Add($commonRoot)
                    }
                }
            }
        }

        foreach ($root in $roots.ToArray()) {
            if (Test-ExcludedPath -Path $root) {
                Add-DiscoveryError -Stage 'SearchPathExcluded' -Target $root -Message 'The path is covered by a default or requested exclusion.'
                continue
            }
            if (-not (Test-Path -LiteralPath $root -PathType Container)) {
                Add-DiscoveryError -Stage 'SearchPath' -Target $root -Message 'The search path does not exist or is not a directory.'
                continue
            }

            $pendingDirectories = New-Object 'System.Collections.Generic.Stack[string]'
            $pendingDirectories.Push($root)
            while ($pendingDirectories.Count -gt 0) {
                $directoryPath = $pendingDirectories.Pop()
                if (Test-ExcludedPath -Path $directoryPath) {
                    continue
                }
                try {
                    $directory = Get-Item -LiteralPath $directoryPath -Force -ErrorAction Stop
                    if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                        continue
                    }
                    foreach ($file in @(Get-ChildItem -LiteralPath $directoryPath -Filter '*.ps1' -File -Force -ErrorAction Stop)) {
                        Add-ScriptCandidate -Path $file.FullName -Source 'SearchPath' -TaskReference ''
                    }
                    foreach ($childDirectory in @(Get-ChildItem -LiteralPath $directoryPath -Directory -Force -ErrorAction Stop)) {
                        if (-not ($childDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                            -not (Test-ExcludedPath -Path $childDirectory.FullName)) {
                            $pendingDirectories.Push($childDirectory.FullName)
                        }
                    }
                }
                catch {
                    Add-DiscoveryError -Stage 'SearchAccess' -Target $directoryPath -Message $_.Exception.Message
                }
            }
        }

        foreach ($candidate in @($candidates.Values | Sort-Object Path)) {
            $candidatePath = $candidate.Path
            if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
                $scripts.Add([pscustomobject] @{
                    ComputerName      = $computer
                    OriginalPath      = $candidatePath
                    DiscoverySources  = $candidate.Sources.ToArray() -join '; '
                    ReferencedByTasks = $candidate.TaskNames.ToArray() -join '; '
                    DeclaredAuthor    = ''
                    FileOwner         = ''
                    LengthBytes       = $null
                    CreatedUtc        = ''
                    LastWriteUtc      = ''
                    SHA256            = ''
                    SourceStatus      = 'Missing'
                })
                Add-DiscoveryError -Stage 'SourceFile' -Target $candidatePath -Message 'The referenced script does not exist or is not accessible.'
                continue
            }

            try {
                $file = Get-Item -LiteralPath $candidatePath -Force -ErrorAction Stop
                if ($file.Length -gt $MaximumFileBytes) {
                    $scripts.Add([pscustomobject] @{
                        ComputerName      = $computer
                        OriginalPath      = $file.FullName
                        DiscoverySources  = $candidate.Sources.ToArray() -join '; '
                        ReferencedByTasks = $candidate.TaskNames.ToArray() -join '; '
                        DeclaredAuthor    = ''
                        FileOwner         = ''
                        LengthBytes       = $file.Length
                        CreatedUtc        = $file.CreationTimeUtc.ToString('o')
                        LastWriteUtc      = $file.LastWriteTimeUtc.ToString('o')
                        SHA256            = ''
                        SourceStatus      = 'TooLarge'
                    })
                    Add-DiscoveryError -Stage 'FileSize' -Target $file.FullName -Message ("The script exceeds the {0} MB limit." -f ($MaximumFileBytes / 1MB))
                    continue
                }

                $declaredAuthor = ''
                try {
                    foreach ($line in @(Get-Content -LiteralPath $file.FullName -TotalCount 100 -ErrorAction Stop)) {
                        if ($line -match '^\s*#\s*(?:Author|Created\s+by)\s*:\s*(?<author>.+?)\s*$') {
                            $declaredAuthor = $Matches.author
                            break
                        }
                    }
                }
                catch {
                    Add-DiscoveryError -Stage 'ReadHeader' -Target $file.FullName -Message $_.Exception.Message
                }

                $owner = ''
                try {
                    $owner = (Get-Acl -LiteralPath $file.FullName -ErrorAction Stop).Owner
                }
                catch {
                    Add-DiscoveryError -Stage 'FileOwner' -Target $file.FullName -Message $_.Exception.Message
                }

                $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                $scripts.Add([pscustomobject] @{
                    ComputerName      = $computer
                    OriginalPath      = $file.FullName
                    DiscoverySources  = $candidate.Sources.ToArray() -join '; '
                    ReferencedByTasks = $candidate.TaskNames.ToArray() -join '; '
                    DeclaredAuthor    = $declaredAuthor
                    FileOwner         = $owner
                    LengthBytes       = $file.Length
                    CreatedUtc        = $file.CreationTimeUtc.ToString('o')
                    LastWriteUtc      = $file.LastWriteTimeUtc.ToString('o')
                    SHA256            = $hash
                    SourceStatus      = 'Ready'
                })
            }
            catch {
                Add-DiscoveryError -Stage 'FileMetadata' -Target $candidatePath -Message $_.Exception.Message
            }
        }

        [pscustomobject] @{
            ComputerName          = $computer
            SearchRoots           = $roots.ToArray()
            Scripts               = $scripts.ToArray()
            Tasks                 = $tasks.ToArray()
            TaskEvents            = $taskEvents.ToArray()
            TaskEventLogStatus    = $taskEventLogStatus
            EventLookbackStartUtc = $eventLookbackStartUtc.ToString('o')
            EventLookbackEndUtc   = $eventLookbackEndUtc.ToString('o')
            Errors                = $errors.ToArray()
            SuppressedErrorCount  = $state.SuppressedErrors
        }
    }

    foreach ($targetComputer in $ComputerName) {
        if ([string]::IsNullOrWhiteSpace($targetComputer)) {
            continue
        }

        $session = $null
        $isLocal = Test-At0mFlowLocalComputer -ComputerName $targetComputer
        try {
            if (-not $isLocal) {
                $sessionParameters = @{
                    ComputerName = $targetComputer
                    ErrorAction  = 'Stop'
                }
                if ($null -ne $Credential) {
                    $sessionParameters.Credential = $Credential
                }
                $session = New-PSSession @sessionParameters
            }

            $discoveryArguments = New-Object 'object[]' 9
            $discoveryArguments[0] = @($SearchPath)
            $discoveryArguments[1] = $ScanFixedDrives.IsPresent
            $discoveryArguments[2] = $SkipScheduledTasks.IsPresent
            $discoveryArguments[3] = $IncludeMicrosoftTaskFolder.IsPresent
            $discoveryArguments[4] = $IncludeDefaultLocations.IsPresent
            $discoveryArguments[5] = @($ExcludePath)
            $discoveryArguments[6] = $(if ($isLocal) { $resolvedOutputPath } else { '' })
            $discoveryArguments[7] = $maximumBytes
            $discoveryArguments[8] = $parserDefinition

            $discovery = if ($isLocal) {
                & $discoveryScript @discoveryArguments
            }
            else {
                Invoke-Command -Session $session -ScriptBlock $discoveryScript -ArgumentList $discoveryArguments -ErrorAction Stop
            }

            $actualComputerName = [string] $discovery.ComputerName
            $searchRootsByComputer[$actualComputerName] = @($discovery.SearchRoots)
            $taskEventLogStatusByComputer[$actualComputerName] = [string] $discovery.TaskEventLogStatus
            $eventLookbackByComputer[$actualComputerName] = [ordered] @{
                StartUtc = [string] $discovery.EventLookbackStartUtc
                EndUtc   = [string] $discovery.EventLookbackEndUtc
            }
            foreach ($task in @($discovery.Tasks)) {
                $taskRows.Add($task)
            }
            foreach ($taskEvent in @($discovery.TaskEvents)) {
                $taskEventRows.Add($taskEvent)
            }
            foreach ($collectionError in @($discovery.Errors)) {
                $errorRows.Add($collectionError)
            }
            if ([int] $discovery.SuppressedErrorCount -gt 0) {
                $errorRows.Add([pscustomobject] @{
                    ComputerName = $actualComputerName
                    Stage        = 'SuppressedErrors'
                    Target       = $actualComputerName
                    Message      = ('{0} additional discovery error(s) were suppressed.' -f $discovery.SuppressedErrorCount)
                })
            }

            foreach ($sourceScript in @($discovery.Scripts)) {
                $centralRelativePath = ConvertTo-At0mFlowCentralPath `
                    -ComputerName $actualComputerName `
                    -OriginalPath $sourceScript.OriginalPath
                $destinationPath = Join-Path $resolvedOutputPath ($centralRelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
                $copyStatus = [string] $sourceScript.SourceStatus
                $previousCollectedHash = ''
                $collectedHash = ''
                $collectionChange = 'Unavailable'
                $repositoryRelativePath = ''
                if ($null -ne $gitContext) {
                    $repositoryRelativePath = if ($gitContext.OutputRelativePath -eq '.') {
                        $centralRelativePath
                    }
                    else {
                        '{0}/{1}' -f $gitContext.OutputRelativePath, $centralRelativePath
                    }
                }

                if ($sourceScript.SourceStatus -eq 'Ready') {
                    if ($InventoryOnly.IsPresent) {
                        $copyStatus = 'InventoryOnly'
                        $collectionChange = 'NotCopied'
                    }
                    else {
                        try {
                            $destinationDirectory = Split-Path -Parent $destinationPath
                            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
                            if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
                                $previousCollectedHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256 -ErrorAction Stop).Hash
                                $collectionChange = if ($previousCollectedHash -eq $sourceScript.SHA256) {
                                    'Unchanged'
                                }
                                else {
                                    'Modified'
                                }
                            }
                            else {
                                $collectionChange = 'Added'
                            }
                            if ($collectionChange -ne 'Unchanged') {
                                if ($isLocal) {
                                    Copy-Item -LiteralPath $sourceScript.OriginalPath -Destination $destinationPath -Force -ErrorAction Stop
                                }
                                else {
                                    Copy-Item -FromSession $session -LiteralPath $sourceScript.OriginalPath -Destination $destinationPath -Force -ErrorAction Stop
                                }
                            }
                            $collectedHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256 -ErrorAction Stop).Hash
                            if ($collectedHash -ne $sourceScript.SHA256) {
                                $copyStatus = 'HashMismatch'
                                $collectionChange = 'HashMismatch'
                                $errorRows.Add([pscustomobject] @{
                                    ComputerName = $actualComputerName
                                    Stage        = 'CopyVerification'
                                    Target       = $sourceScript.OriginalPath
                                    Message      = 'The copied file hash does not match the source hash.'
                                })
                            }
                            else {
                                $copyStatus = 'Copied'
                            }
                        }
                        catch {
                            $copyStatus = 'CopyFailed'
                            $collectionChange = 'CopyFailed'
                            $errorRows.Add([pscustomobject] @{
                                ComputerName = $actualComputerName
                                Stage        = 'Copy'
                                Target       = $sourceScript.OriginalPath
                                Message      = $_.Exception.Message
                            })
                        }
                    }
                }

                $scriptRows.Add([pscustomobject] @{
                    ComputerName        = $actualComputerName
                    OriginalPath        = $sourceScript.OriginalPath
                    CentralRelativePath = $centralRelativePath
                    SourcePhysicalPath  = $sourceScript.OriginalPath
                    CollectedCopyPath   = $destinationPath
                    RepositoryRelativePath = $repositoryRelativePath
                    DiscoverySources    = $sourceScript.DiscoverySources
                    ReferencedByTasks   = $sourceScript.ReferencedByTasks
                    DeclaredAuthor      = $sourceScript.DeclaredAuthor
                    FileOwner           = $sourceScript.FileOwner
                    LengthBytes         = $sourceScript.LengthBytes
                    CreatedUtc          = $sourceScript.CreatedUtc
                    LastWriteUtc        = $sourceScript.LastWriteUtc
                    SHA256              = $sourceScript.SHA256
                    PreviousCollectedSHA256 = $previousCollectedHash
                    CollectedSHA256     = $collectedHash
                    CollectionChange    = $collectionChange
                    CopyStatus          = $copyStatus
                })
            }
        }
        catch {
            $errorRows.Add([pscustomobject] @{
                ComputerName = $targetComputer
                Stage        = 'ComputerCollection'
                Target       = $targetComputer
                Message      = $_.Exception.Message
            })
        }
        finally {
            if ($null -ne $session) {
                Remove-PSSession -Session $session
            }
        }
    }

    $scriptArray = $scriptRows.ToArray()
    $taskArray = $taskRows.ToArray()
    $taskEventArray = $taskEventRows.ToArray()
    $errorArray = $errorRows.ToArray()
    $executionEvidenceRows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($evidenceComputer in @($scriptArray | Select-Object -ExpandProperty ComputerName -Unique)) {
        $lookback = $eventLookbackByComputer[$evidenceComputer]
        $evidence = ConvertTo-At0mFlowExecutionEvidence `
            -Scripts @($scriptArray | Where-Object ComputerName -eq $evidenceComputer) `
            -Tasks @($taskArray | Where-Object ComputerName -eq $evidenceComputer) `
            -TaskEvents @($taskEventArray | Where-Object ComputerName -eq $evidenceComputer) `
            -EventLogStatus ([string] $taskEventLogStatusByComputer[$evidenceComputer]) `
            -LookbackStartUtc ([string] $lookback.StartUtc) `
            -LookbackEndUtc ([string] $lookback.EndUtc)
        foreach ($evidenceRow in @($evidence)) {
            $executionEvidenceRows.Add($evidenceRow)
        }
    }
    $executionEvidenceArray = $executionEvidenceRows.ToArray()
    $scriptProperties = @(
        'ComputerName', 'OriginalPath', 'CentralRelativePath',
        'SourcePhysicalPath', 'CollectedCopyPath', 'RepositoryRelativePath',
        'DiscoverySources', 'ReferencedByTasks', 'DeclaredAuthor', 'FileOwner',
        'LengthBytes', 'CreatedUtc', 'LastWriteUtc', 'SHA256',
        'PreviousCollectedSHA256', 'CollectedSHA256', 'CollectionChange',
        'CopyStatus'
    )
    $taskProperties = @(
        'ComputerName', 'TaskName', 'TaskPath', 'State', 'Author', 'Description',
        'Principal', 'RunLevel', 'LogonType', 'ActionIndex', 'ActionExecute',
        'ActionArguments', 'WorkingDirectory', 'ScriptReferences',
        'IncludedScriptReferences', 'ExcludedScriptReferences', 'Triggers',
        'Conditions', 'LastRunUtc', 'NextRunUtc', 'LastTaskResult'
    )
    $errorProperties = @('ComputerName', 'Stage', 'Target', 'Message')
    $executionEvidenceProperties = @(
        'ComputerName', 'SourcePhysicalPath', 'CollectedCopyPath',
        'RepositoryRelativePath', 'CentralRelativePath', 'EvidenceStatus',
        'Outcome', 'IsFailure', 'Attribution', 'EventTimeUtc', 'EventId',
        'EventRecordId', 'TaskName', 'TaskPath', 'Action', 'ResultCode',
        'EvidenceKey', 'EvidenceSource', 'LookbackStartUtc', 'LookbackEndUtc'
    )

    $scriptInventoryPath = Join-Path $manifestsPath 'script-inventory.csv'
    $scheduledTasksPath = Join-Path $manifestsPath 'scheduled-tasks.csv'
    $errorsPath = Join-Path $manifestsPath 'collection-errors.csv'
    $executionEvidencePath = Join-Path $manifestsPath 'script-run-evidence.csv'
    Export-At0mFlowCsv -InputObject $scriptArray -Property $scriptProperties -Path $scriptInventoryPath
    Export-At0mFlowCsv -InputObject $taskArray -Property $taskProperties -Path $scheduledTasksPath
    Export-At0mFlowCsv -InputObject $errorArray -Property $errorProperties -Path $errorsPath
    Export-At0mFlowCsv `
        -InputObject $executionEvidenceArray `
        -Property $executionEvidenceProperties `
        -Path $executionEvidencePath

    $completedAtUtc = [DateTimeOffset]::UtcNow
    $summary = [ordered] @{
        Tool                  = 'At0mFlow Script Audit'
        Version               = '1.1.0'
        StartedAtUtc          = $startedAtUtc
        CompletedAtUtc        = $completedAtUtc
        OutputPath            = $resolvedOutputPath
        GitWorkingTreeRoot    = $(if ($null -ne $gitContext) { $gitContext.RootPath } else { '' })
        GitOutputRelativePath = $(if ($null -ne $gitContext) { $gitContext.OutputRelativePath } else { '' })
        GitSyncRequested      = $GitSync.IsPresent
        InventoryOnly         = $InventoryOnly.IsPresent
        ComputerCount         = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
        ScriptCount           = $scriptArray.Count
        CopiedCount           = @($scriptArray | Where-Object CopyStatus -eq 'Copied').Count
        AddedCount            = @($scriptArray | Where-Object CollectionChange -eq 'Added').Count
        ModifiedCount         = @($scriptArray | Where-Object CollectionChange -eq 'Modified').Count
        UnchangedCount        = @($scriptArray | Where-Object CollectionChange -eq 'Unchanged').Count
        ScheduledTaskCount    = $taskArray.Count
        ExecutionEvidenceLookbackHours = 1
        ExecutionEvidenceCount = @($executionEvidenceArray | Where-Object EvidenceStatus -eq 'Observed').Count
        ExecutionFailureCount = @($executionEvidenceArray | Where-Object IsFailure -eq 'True').Count
        TaskEventLogStatusByComputer = $taskEventLogStatusByComputer
        ErrorCount            = $errorArray.Count
        HasErrors             = $errorArray.Count -gt 0
        SearchRootsByComputer = $searchRootsByComputer
    }
    $summaryPath = Join-Path $manifestsPath 'summary.json'
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-At0mFlowBundleTree -ScriptsPath $scriptsPath -TreePath (Join-Path $manifestsPath 'TREE.txt')

    @(
        'At0mFlow Script Audit bundle'
        '============================'
        ''
        'This bundle can contain confidential source code and infrastructure metadata.'
        'Keep it private. Review scripts for credentials before using Git or sharing it.'
        ''
        'scripts/ contains the preserved per-computer folder tree.'
        'manifests/script-inventory.csv records file metadata and hashes.'
        'manifests/scheduled-tasks.csv records PowerShell task actions, triggers and conditions.'
        'manifests/collection-errors.csv records access and collection gaps.'
        'manifests/script-run-evidence.csv records one hour of local Task Scheduler outcome evidence.'
        'manifests/summary.json records run totals.'
        'manifests/TREE.txt shows the collected folder tree.'
        ''
        'The collector did not initialise Git, create a remote, upload this bundle or send telemetry.'
        'For deeper estate analysis, documentation and migration planning, visit https://at0mflow.com.'
    ) | Set-Content -LiteralPath (Join-Path $resolvedOutputPath 'README.txt') -Encoding UTF8

    $gitSyncStatus = 'NotRequested'
    $gitCommit = ''
    if ($GitSync.IsPresent) {
        $gitResult = Invoke-At0mFlowGitSync `
            -Context $gitContext `
            -CommitMessage $GitCommitMessage
        $gitSyncStatus = $gitResult.Status
        $gitCommit = $gitResult.Commit
    }

    [pscustomobject] @{
        PSTypeName         = 'At0mFlow.ScriptAudit.Report'
        StartedAtUtc       = $startedAtUtc
        CompletedAtUtc     = $completedAtUtc
        OutputPath         = $resolvedOutputPath
        GitWorkingTreeRoot = $(if ($null -ne $gitContext) { $gitContext.RootPath } else { '' })
        GitOutputRelativePath = $(if ($null -ne $gitContext) { $gitContext.OutputRelativePath } else { '' })
        GitSyncStatus      = $gitSyncStatus
        GitCommit          = $gitCommit
        ComputerCount      = $summary.ComputerCount
        ScriptCount        = $summary.ScriptCount
        CopiedCount        = $summary.CopiedCount
        ScheduledTaskCount = $summary.ScheduledTaskCount
        ExecutionEvidenceCount = $summary.ExecutionEvidenceCount
        ExecutionFailureCount = $summary.ExecutionFailureCount
        ErrorCount         = $summary.ErrorCount
        HasErrors          = $summary.HasErrors
        InventoryOnly      = $summary.InventoryOnly
        Scripts            = $scriptArray
        ScheduledTasks     = $taskArray
        ExecutionEvidence  = $executionEvidenceArray
        Errors             = $errorArray
    }
}

function Write-At0mFlowScriptAuditReport {
    <#
    .SYNOPSIS
    Writes a concise console summary for an At0mFlow Script Audit report.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This function exists specifically to render interactive console output.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Report,

        [switch] $NoBanner
    )

    process {
        if (-not $NoBanner.IsPresent) {
            Write-At0mFlowWordmark
        }

        Write-Host ''
        Write-Host 'At0mFlow Script Audit' -ForegroundColor Cyan
        Write-Host ('Computers: {0}' -f $Report.ComputerCount)
        Write-Host ('Scripts found: {0}' -f $Report.ScriptCount)
        Write-Host ('Scripts copied: {0}' -f $Report.CopiedCount)
        if ($Report.PSObject.Properties.Name -contains 'GitSyncStatus') {
            Write-Host ('Git sync: {0}' -f $Report.GitSyncStatus)
        }
        Write-Host ('PowerShell task actions: {0}' -f $Report.ScheduledTaskCount)
        if ($Report.PSObject.Properties.Name -contains 'ExecutionEvidenceCount') {
            Write-Host ('Execution evidence: {0}' -f $Report.ExecutionEvidenceCount)
            Write-Host ('Execution failures: {0}' -f $Report.ExecutionFailureCount)
        }
        $errorColour = if ($Report.HasErrors) { 'Yellow' } else { 'Green' }
        Write-Host ('Collection errors: {0}' -f $Report.ErrorCount) -ForegroundColor $errorColour
        Write-Host ('Bundle: {0}' -f $Report.OutputPath) -ForegroundColor DarkCyan
        Write-Host ''
        Write-Host 'Treat the bundle as confidential before using Git or sharing it.' -ForegroundColor Yellow
        Write-Host ''
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-At0mFlowCentralPath'
    'Get-At0mFlowTaskScriptReference'
    'Invoke-At0mFlowScriptAudit'
    'Write-At0mFlowScriptAuditReport'
)
