[CmdletBinding()]
param(
    [switch] $Staged
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object 'System.Collections.Generic.List[string]'

$allowedTopLevel = @(
    '.gitattributes',
    '.github',
    '.githooks',
    '.gitignore',
    'AGENTS.md',
    'assets',
    'CONTRIBUTING.md',
    'docs',
    'examples',
    'LICENSE',
    'PUBLIC_BOUNDARY.md',
    'README.md',
    'requirements.md',
    'scripts',
    'SECURITY.md',
    'src',
    'tests'
)

$blockedTopLevel = @(
    '.openai',
    '.wrangler',
    'app',
    'audit-output',
    'branding',
    'build',
    'collected-scripts',
    'db',
    'dist',
    'drizzle',
    'lib',
    'marketing',
    'node_modules',
    'public',
    'worker'
)

$blockedFileNames = @(
    '.dev.vars',
    '.env',
    '.env.local',
    '.npmrc',
    '.pypirc',
    'credentials.json',
    'id_ed25519',
    'id_rsa',
    'package-lock.json',
    'package.json',
    'wrangler.json',
    'wrangler.jsonc',
    'wrangler.toml'
)

$blockedExtensions = @(
    '.bak', '.cs', '.db', '.dll', '.dylib', '.exe', '.jks', '.js', '.jsx',
    '.kdbx', '.key', '.keystore', '.mjs', '.p12', '.pem', '.pfx', '.py',
    '.so', '.sql', '.sqlite', '.sqlite3', '.ts', '.tsx', '.zip'
)

$credentialPatterns = @(
    '(?i)-----BEGIN (?:EC |OPENSSH |RSA )?PRIVATE KEY-----',
    '(?i)\b(?:OPENAI_API_KEY|CLOUDFLARE_API_TOKEN|STRIPE_SECRET_KEY|BETTER_AUTH_SECRET|DATABASE_URL)\s*=',
    '(?i)\b(?:github_pat_|ghp_|sk_live_|sk-proj-)[A-Za-z0-9_-]{12,}',
    '\bAKIA[0-9A-Z]{16}\b',
    '\bAIza[0-9A-Za-z_-]{35}\b',
    '(?i)\bxox[baprs]-[A-Za-z0-9-]{10,}',
    '(?i)\b(?:AccountKey|SharedAccessSignature)\s*=\s*[^;\s]{12,}',
    '(?i)\b(?:password|passwd|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*["''][^"'']{8,}["'']'
)

$personalDataPatterns = @(
    '(?i)\b[A-Z0-9._%+-]+@(?!example\.(?:com|org|net)\b)[A-Z0-9.-]+\.[A-Z]{2,}\b',
    '(?i)\bC:\\Users\\(?!Public\\)[^\\\s]+\\',
    '(?i)\b/(?:home|Users)/(?!runner(?:/|\b))[^/\s]+/',
    ('(?i)\b(?:' + 'Papi' + 'Paragon|Circuit' + 'Danny|Company' + '_Startup_V1)\b')
)

Push-Location $repositoryRoot
try {
    if ($Staged.IsPresent) {
        $relativePaths = @(
            git diff --cached --name-only --diff-filter=ACMR 2>$null |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }
    elseif (Test-Path -LiteralPath (Join-Path $repositoryRoot '.git')) {
        $relativePaths = @(
            git ls-files 2>$null |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }
    else {
        $relativePaths = @(
            Get-ChildItem -LiteralPath $repositoryRoot -File -Recurse |
                ForEach-Object { $_.FullName.Substring($repositoryRoot.Length + 1).Replace('\', '/') }
        )
    }

    foreach ($relativePath in $relativePaths) {
        $normalisedPath = $relativePath.Replace('\', '/')
        $pathParts = $normalisedPath.Split('/')
        $topLevel = $pathParts[0]
        $fileName = $pathParts[$pathParts.Count - 1]
        $extension = [IO.Path]::GetExtension($fileName).ToLowerInvariant()

        if ($allowedTopLevel -notcontains $topLevel) {
            $failures.Add("Unexpected top-level path: $normalisedPath")
        }
        if (($blockedTopLevel -contains $topLevel) -or
            ($topLevel -like 'At0mFlow-ScriptAudit-*')) {
            $failures.Add("Generated bundle or product path: $normalisedPath")
        }
        if (($blockedFileNames -contains $fileName) -or ($fileName -like '.env.*')) {
            $failures.Add("Blocked configuration file: $normalisedPath")
        }
        if ($blockedExtensions -contains $extension) {
            $failures.Add("Unexpected source or private file type: $normalisedPath")
        }
        if (($extension -eq '.csv') -and ($topLevel -ne 'examples')) {
            $failures.Add("CSV files are allowed only as synthetic examples: $normalisedPath")
        }
        if (($extension -in @('.ps1', '.psm1', '.psd1')) -and
            ($topLevel -notin @('examples', 'scripts', 'src', 'tests'))) {
            $failures.Add("PowerShell source is in an unexpected path: $normalisedPath")
        }

        $fullPath = Join-Path $repositoryRoot $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            continue
        }

        $fileInfo = Get-Item -LiteralPath $fullPath -Force
        if ($fileInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $failures.Add("Symbolic links and reparse points are not allowed: $normalisedPath")
            continue
        }
        if ($fileInfo.Length -gt 2MB) {
            $failures.Add("File exceeds the 2 MB public-repository limit: $normalisedPath")
            continue
        }
        if ($extension -in @('.png', '.jpg', '.jpeg', '.gif', '.webp')) {
            continue
        }

        $content = Get-Content -LiteralPath $fullPath -Raw -ErrorAction SilentlyContinue
        if ($null -eq $content) {
            continue
        }
        foreach ($pattern in $credentialPatterns) {
            if ($content -match $pattern) {
                $failures.Add("Possible credential or private key in: $normalisedPath")
                break
            }
        }
        foreach ($pattern in $personalDataPatterns) {
            if ($content -match $pattern) {
                $failures.Add("Possible personal or machine-identifying data in: $normalisedPath")
                break
            }
        }
    }

    if (Test-Path -LiteralPath (Join-Path $repositoryRoot '.git')) {
        $remotes = @(git remote)
        if ($remotes -contains 'origin') {
            $origin = git remote get-url origin
            $validRemote = $origin -match '^(?:https://github\.com/At0mFlow/At0mFlow-ScriptAudit(?:\.git)?|git@github\.com:At0mFlow/At0mFlow-ScriptAudit\.git)$'
            if (-not $validRemote) {
                $failures.Add("Unexpected origin remote: $origin")
            }
        }

        $linkEntries = @(git ls-files -s 2>$null | Where-Object { $_ -match '^120000 ' })
        foreach ($linkEntry in $linkEntries) {
            $failures.Add("Git symbolic link is not allowed: $linkEntry")
        }
    }
}
finally {
    Pop-Location
}

if ($failures.Count -gt 0) {
    $failures | Sort-Object -Unique | ForEach-Object { Write-Error $_ }
    throw "Public boundary check failed with $($failures.Count) issue(s)."
}

Write-Host "Public boundary check passed for $($relativePaths.Count) file(s)." -ForegroundColor Green
