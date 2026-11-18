#requires -Version 5.1

function git-profile {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('list', 'current', 'use', 'check', 'status', 'help')]
        [string]$Action = 'help',

        [Parameter(Position = 1)]
        [string]$Profile
    )

    function Invoke-ProfileGit {
        param([string[]]$GitArguments, [switch]$AllowMissing)
        $consoleEncoding = [Console]::OutputEncoding
        $restoreEncoding = $consoleEncoding.CodePage -ne 65001
        # Git returns branch and remote names in UTF-8.
        if ($restoreEncoding) { [Console]::OutputEncoding = [Text.Encoding]::UTF8 }
        try {
            $output = @(& git @GitArguments 2>&1)
            $code = $LASTEXITCODE
        }
        finally {
            if ($restoreEncoding) { [Console]::OutputEncoding = $consoleEncoding }
        }
        if ($code -ne 0) {
            if ($AllowMissing -and $code -eq 1) { return }
            throw "Git failed (exit code $code): $($output -join [Environment]::NewLine)"
        }
        $output | ForEach-Object { $_.ToString() }
    }

    function Read-ProfileRemote {
        param([string]$Url)
        if ($Url -notmatch '^https://(?:(?<Account>[a-z0-9-]+)@)?github\.com/(?<Owner>[a-z0-9-]+)/(?<Repo>[a-z0-9_.-]+?)(?:\.git)?/?$') {
            throw 'This alpha only supports HTTPS origin URLs on github.com, without passwords, query strings, or fragments.'
        }
        [pscustomobject]@{
            Account = $Matches.Account
            Owner = $Matches.Owner
            Repo = $Matches.Repo
        }
    }

    if ($Action -eq 'help') {
        Write-Host 'git-profile v0.1.0-alpha.2' -ForegroundColor Cyan
        Write-Host 'Usage: git-profile list | current | use PROFILE | check | status'
        return
    }

    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'Git was not found on PATH.'
    }
    $configPath = Join-Path $PSScriptRoot 'profiles.psd1'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "profiles.psd1 is missing. Copy profiles.example.psd1 and configure your accounts in $PSScriptRoot."
    }
    $profiles = Import-PowerShellDataFile -LiteralPath $configPath -ErrorAction Stop
    if ($profiles.Count -eq 0) { throw 'No profiles are configured.' }
    $accounts = @()
    foreach ($key in $profiles.Keys) {
        $p = $profiles[$key]
        if ($key -notmatch '^[a-z0-9_-]+$' -or $p -isnot [hashtable] -or
            $p.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($p.Name) -or
            $p.Email -isnot [string] -or $p.Email -notmatch '^[^\s<>@]+@[^\s<>@]+$' -or
            $p.GitHub -isnot [string] -or $p.GitHub -notmatch '^[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?$' -or
            $p.Name -match '[\r\n<>]' -or $accounts -contains $p.GitHub) {
            throw "Invalid profile '$key' or duplicate GitHub account. Check profiles.psd1."
        }
        $accounts += $p.GitHub
    }

    if ($Action -eq 'list') {
        Write-Host 'AVAILABLE PROFILES' -ForegroundColor Cyan
        foreach ($key in ($profiles.Keys | Sort-Object)) {
            $p = $profiles[$key]
            Write-Host "`nProfile : $key" -ForegroundColor Yellow
            Write-Host "Name   : $($p.Name)`nEmail  : $($p.Email)`nGitHub : $($p.GitHub)"
        }
        return
    }
    if ($Action -eq 'use' -and ([string]::IsNullOrWhiteSpace($Profile) -or -not $profiles.ContainsKey($Profile))) {
        throw 'Profile not found. Run git-profile list.'
    }
    if ((Invoke-ProfileGit -GitArguments @('rev-parse', '--is-inside-work-tree')) -ne 'true') {
        throw 'Run this command inside a Git working tree.'
    }
    if ($Action -eq 'use') {
        $gitConfigPath = Invoke-ProfileGit -GitArguments @('rev-parse', '--path-format=absolute', '--git-path', 'config')
        if ((Get-Item -LiteralPath $gitConfigPath).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'This alpha cannot modify a linked Git config file.'
        }
        $originalConfig = [IO.File]::ReadAllBytes($gitConfigPath)
    }

    $name = Invoke-ProfileGit -GitArguments @('config', '--local', '--get', 'user.name') -AllowMissing
    $email = Invoke-ProfileGit -GitArguments @('config', '--local', '--get', 'user.email') -AllowMissing
    $rawFetch = @(Invoke-ProfileGit -GitArguments @('config', '--get-all', 'remote.origin.url') -AllowMissing)
    $rawPush = @(Invoke-ProfileGit -GitArguments @('config', '--get-all', 'remote.origin.pushurl') -AllowMissing)
    if ($rawFetch.Count -ne 1 -or $rawPush.Count -gt 1) {
        throw 'The origin remote must have one fetch URL and at most one explicit push URL.'
    }
    $fetch = @(Invoke-ProfileGit -GitArguments @('remote', 'get-url', '--all', 'origin'))
    $push = @(Invoke-ProfileGit -GitArguments @('remote', 'get-url', '--push', '--all', 'origin'))
    if ($fetch.Count -ne 1 -or $push.Count -ne 1) {
        throw 'This alpha requires exactly one effective fetch URL and one effective push URL.'
    }

    $matchedProfile = $null
    foreach ($key in $profiles.Keys) {
        if ($name -eq $profiles[$key].Name -and $email -eq $profiles[$key].Email) {
            $matchedProfile = $key
            break
        }
    }
    if ($Action -in @('current', 'status')) {
        Write-Host 'LOCAL REPOSITORY CONFIGURATION' -ForegroundColor Cyan
        Write-Host "Name   : $name`nEmail  : $email`nOrigin fetch : $($fetch[0])`nOrigin push  : $($push[0])"
        Write-Host "Profile : $(if ($matchedProfile) { $matchedProfile } else { 'no match' })"
        if ($Action -eq 'current') { return }
    }

    if ($Action -in @('check', 'status')) {
        $head = Invoke-ProfileGit -GitArguments @('symbolic-ref', '--quiet', 'HEAD') -AllowMissing
        $pushRemoteKeys = @('remote.pushDefault')
        if ($head -cmatch '^refs/heads/(.+)$') {
            $branch = $Matches[1]
            $pushRemoteKeys = @("branch.$branch.pushRemote", 'remote.pushDefault', "branch.$branch.remote")
        }

        foreach ($key in $pushRemoteKeys) {
            # The NUL terminator distinguishes an empty value from a missing key.
            $value = Invoke-ProfileGit -GitArguments @('config', '--null', '--get', $key) -AllowMissing
            if ($null -eq $value) { continue }

            $pushRemote = ($value -join "`n").TrimEnd([char]0)
            if ($pushRemote -cne 'origin') {
                $destination = 'a destination without a configured remote'
                if ((Invoke-ProfileGit -GitArguments @('remote')) -ccontains $pushRemote) {
                    $destination = "remote '$pushRemote'"
                }
                throw "Running git push without arguments selects $destination because of $key. The profile only validates origin."
            }
            break
        }
        if ($Action -eq 'status') { Write-Host 'Default push remote : origin' }
    }

    if ($Action -eq 'use') {
        $p = $profiles[$Profile]
        $expected = $p.GitHub
    }
    else {
        if (-not $matchedProfile) { throw 'The local identity does not match any configured profile.' }
        $p = $profiles[$matchedProfile]
        $expected = $p.GitHub
    }

    $parsed = @()
    foreach ($url in @($rawFetch + $rawPush + $fetch + $push)) {
        $remote = Read-ProfileRemote -Url $url
        if ($remote.Owner -ne $expected) {
            throw "Repository owner '$($remote.Owner)' does not match account '$expected'. No changes were made."
        }
        $parsed += $remote
    }
    foreach ($remote in $parsed) {
        if ($remote.Repo -ne $parsed[0].Repo) {
            throw 'The fetch and push URLs must point to the same repository.'
        }
    }

    if ($Action -eq 'use') {
        $lockPath = $gitConfigPath + '.lock'
        $ownsLock = $false
        try {
            # The lock prevents partial writes and keeps other Git processes from writing concurrently.
            $stream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $ownsLock = $true
            try {
                if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($gitConfigPath)) -ne [Convert]::ToBase64String($originalConfig)) {
                    throw 'The configuration changed during validation. Run the command again.'
                }
                $stream.Write($originalConfig, 0, $originalConfig.Length)
            }
            finally { $stream.Dispose() }

            $null = Invoke-ProfileGit -GitArguments @('config', '--file', $lockPath, 'user.name', $p.Name)
            $null = Invoke-ProfileGit -GitArguments @('config', '--file', $lockPath, 'user.email', $p.Email)
            $newFetch = $rawFetch[0] -replace '^https://(?:[^@/]+@)?github\.com/', "https://$expected@github.com/"
            $null = Invoke-ProfileGit -GitArguments @('config', '--file', $lockPath, 'remote.origin.url', $newFetch)
            if ($rawPush.Count -eq 1) {
                $newPush = $rawPush[0] -replace '^https://(?:[^@/]+@)?github\.com/', "https://$expected@github.com/"
                $null = Invoke-ProfileGit -GitArguments @('config', '--file', $lockPath, 'remote.origin.pushurl', $newPush)
            }
            [IO.File]::Replace($lockPath, $gitConfigPath, [NullString]::Value)
            $ownsLock = $false
        }
        finally {
            if ($ownsLock -and (Test-Path -LiteralPath $lockPath)) {
                Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop
            }
        }
        Write-Host "PROFILE CONFIGURED: $Profile" -ForegroundColor Green
        Write-Host "Name   : $($p.Name)`nEmail  : $($p.Email)`nGitHub : $expected"
        return
    }

    foreach ($remote in $parsed) {
        if ($remote.Account -ne $expected) {
            throw "The username in a remote URL does not match '$expected'. Run git-profile use $matchedProfile."
        }
    }
    $effectiveName = Invoke-ProfileGit -GitArguments @('config', '--get', 'user.name') -AllowMissing
    $effectiveEmail = Invoke-ProfileGit -GitArguments @('config', '--get', 'user.email') -AllowMissing
    if ($effectiveName -ne $p.Name -or $effectiveEmail -ne $p.Email) {
        throw 'Another configuration setting overrides the local identity. Check git config --show-origin.'
    }
    foreach ($role in @('AUTHOR', 'COMMITTER')) {
        $ident = Invoke-ProfileGit -GitArguments @('var', "GIT_$($role)_IDENT")
        if ($ident -notmatch '^(?<Name>.*) <(?<Email>[^<>]+)> \d+ [+-]\d{4}$' -or
            $Matches.Name -ne $p.Name -or $Matches.Email -ne $p.Email) {
            throw "The effective $role identity does not match the profile. Check author.*, committer.*, and the Git environment variables."
        }
    }
    Write-Host "OK  Profile : $matchedProfile`nOK  GitHub  : $expected`nOK  Name    : $name`nOK  Email   : $email" -ForegroundColor Green
    Write-Host "OK  Origin fetch : $($fetch[0])`nOK  Origin push  : $($push[0])" -ForegroundColor Green
    Write-Host 'Configuration checks passed. Verify authentication and remote permissions separately.'
}
