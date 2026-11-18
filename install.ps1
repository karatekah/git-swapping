#requires -Version 5.1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal/ProfileFiles.ps1')

if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'Git was not found on PATH.'
}

$cliPath = Join-Path $PSScriptRoot 'git-profile.ps1'
$configPath = Join-Path $PSScriptRoot 'profiles.psd1'
$createConfig = -not (Test-Path -LiteralPath $configPath)
if ($createConfig) {
    $profiles = @{}
    do {
        $label = (Read-Host 'Profile name (for example, personal)').Trim()
        if ($label -notmatch '^[a-z0-9_-]+$' -or $profiles.ContainsKey($label)) {
            throw 'Enter a unique profile name using letters, numbers, underscores, or hyphens. Run install.ps1 again.'
        }
        $profiles[$label] = Read-ProfileFields
    } while ((Read-Host 'Add another profile? [y/N]').Trim() -match '^y(?:es)?$')
}
else {
    $profiles = Import-PowerShellDataFile -LiteralPath $configPath
}
& (Join-Path $PSScriptRoot 'internal/Assert-Profiles.ps1') $profiles

$shellProfilePath = $PROFILE.CurrentUserCurrentHost
$profileExists = Test-Path -LiteralPath $shellProfilePath
$registered = $false
foreach ($path in (@($PROFILE.CurrentUserAllHosts, $shellProfilePath) | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "Fix the syntax errors in your PowerShell profile and try again: $path" }
    # Recognize the literal dot-source line used by earlier manual installs too.
    if ($ast.Find({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and
            $node.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Dot -and
            $node.GetCommandName() -eq $cliPath
    }, $true)) {
        $registered = $true
        break
    }
}

if (-not $registered) {
    $original = if ($profileExists) { [string](Get-Content -LiteralPath $shellProfilePath -Raw) } else { '' }
    $quotedPath = [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($cliPath)
    $loader = "if (Test-Path -LiteralPath '$quotedPath' -PathType Leaf) { . '$quotedPath' } # GithubSwapping loader"
    $managedLine = [regex]::Match($original, '(?m)^if \(Test-Path -LiteralPath [^\r\n]+ # GithubSwapping loader(?=\r?$)')
    if ($managedLine.Success) {
        $updated = $original.Remove($managedLine.Index, $managedLine.Length).Insert($managedLine.Index, $loader)
    }
    else {
        $updated = if ($original.Length) { $original + [Environment]::NewLine } else { '' }
        $updated += $loader + [Environment]::NewLine
    }
    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($updated, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "The loader cannot be added to this PowerShell profile: $shellProfilePath" }
}

if ($createConfig) {
    $lines = @('@{')
    foreach ($label in ($profiles.psbase.Keys | Sort-Object)) {
        $lines += Format-ProfileEntry $label $profiles[$label]
    }
    $lines += '}', ''
    Write-LocalFile -Path $configPath -Content ($lines -join [Environment]::NewLine)
}

if (-not $registered) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $shellProfilePath))
    if ($profileExists) {
        $backupPath = "$shellProfilePath.$([guid]::NewGuid().ToString('N')).bak"
        Write-LocalFile -Path $shellProfilePath -Content $updated -BackupPath $backupPath
        Write-Host "PowerShell profile backup: $backupPath"
    }
    else {
        Write-LocalFile -Path $shellProfilePath -Content $updated
    }
}

. $cliPath
Set-Item -Path Function:global:git-profile -Value ${function:git-profile}
Write-Host 'GithubSwapping is ready. Run git-profile list.' -ForegroundColor Green
