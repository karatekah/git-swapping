function Invoke-ProfileGit {
    param([string[]]$GitArguments, [switch]$AllowMissing, [switch]$Raw)

    # Quote Windows arguments explicitly so PowerShell 5.1 preserves literal quotes.
    $arguments = foreach ($argument in $GitArguments) {
        '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
    }
    $start = [Diagnostics.ProcessStartInfo]::new($gitExecutable, ($arguments -join ' '))
    $start.WorkingDirectory = (Get-Location).ProviderPath
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.EnvironmentVariables['LC_ALL'] = 'C'
    # Inspect the same configuration that Git uses for repository operations.
    $start.EnvironmentVariables.Remove('GIT_CONFIG')

    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $output = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        $code = $process.ExitCode
    }
    finally { $process.Dispose() }

    if ($code -ne 0) {
        if ($AllowMissing -and $code -eq 1) { return }
        # Git errors can include unsanitized URLs or configuration values.
        throw "Git $($GitArguments[0]) failed (exit code $code)."
    }
    if ($Raw) { return $output }
    if ($output.Length) { ($output -replace '\r?\n\z', '') -split '\r?\n' }
}

function Get-ProfileGitSetting {
    param([string]$Key)

    $value = Invoke-ProfileGit @('config', '--null', '--show-scope', '--show-origin', '--get', $Key) -AllowMissing -Raw
    if ($null -eq $value) { return }
    $scope, $source, $setting = $value.Split([char]0)
    [pscustomobject]@{ Value = $setting[0]; Source = "$Key [$scope, $source]" }
}

function Get-ProfileGitValues {
    param([string[]]$GitArguments)

    $value = Invoke-ProfileGit $GitArguments -AllowMissing -Raw
    if ($null -ne $value) { $value.Substring(0, $value.Length - 1).Split([char]0) }
}

function Get-ProfileRemote {
    param([string]$Url)

    if ($Url -match '\Ahttps://(?:(?<Account>[a-z0-9-]+)@)?github\.com/(?<Owner>[a-z0-9-]+)/(?<Repo>[a-z0-9_.-]+?)(?:\.git)?/?\z') {
        [pscustomobject]@{ Account = $Matches.Account; Owner = $Matches.Owner; Repo = $Matches.Repo }
    }
}

function Assert-ProfileDestination {
    param($Remote, [string]$Owner, [string]$Repository)

    if (-not $Remote) {
        throw 'Only HTTPS origin URLs on github.com are supported. Remove passwords, query strings, or fragments from the URL.'
    }
    if ($Remote.Owner -ne $Owner) {
        throw "Repository owner '$($Remote.Owner)' does not match account '$Owner'."
    }
    if ($Remote.Repo -ne $Repository) {
        throw 'The fetch and push URLs must point to the same repository.'
    }
}

function Get-ProfilePushRemote {
    $head = Invoke-ProfileGit @('symbolic-ref', '--quiet', 'HEAD') -AllowMissing
    $keys = @('remote.pushDefault')
    if ($head -cmatch '^refs/heads/(.+)$') {
        $branch = $Matches[1]
        $keys = @("branch.$branch.pushRemote", 'remote.pushDefault', "branch.$branch.remote")
    }
    foreach ($key in $keys) {
        $setting = Get-ProfileGitSetting $key
        if ($setting) { return $setting }
    }
    [pscustomobject]@{ Value = 'origin'; Source = 'Git default' }
}

function Get-ProfileIdentitySource {
    param([string]$Role, [string]$Field)

    $environmentKey = "GIT_$($Role)_$($Field.ToUpperInvariant())"
    if (Test-Path -LiteralPath "Env:$environmentKey") { return $environmentKey }
    $setting = Get-ProfileGitSetting "$($Role.ToLowerInvariant()).$Field"
    if (-not $setting) { $setting = Get-ProfileGitSetting "user.$Field" }
    if ($setting) { return $setting.Source }
    if ($Field -eq 'email' -and (Test-Path -LiteralPath 'Env:EMAIL')) { return 'EMAIL' }
    'Git defaults'
}

function Test-ProfileUrls {
    param($Settings, [string]$Fetch, [string]$Push, $Origin, [string]$Account)

    $newFetch = $Settings['remote.origin.url']
    $newPush = $Settings['remote.origin.pushurl']
    if (($newFetch -cne $Fetch -or [string]$newPush -cne $Push) -and
        (Invoke-ProfileGit @('config', '--name-only', '--get-regexp', '^includeif\.hasconfig:remote\.\*\.url:') -AllowMissing)) {
        throw 'Git configuration depends on remote URLs. Set origin to the intended HTTPS account before applying a profile.'
    }
    $rewriteKeys = Get-ProfileGitValues @('config', '--null', '--name-only', '--get-regexp', '^url\..*\.(insteadof|pushinsteadof)$')
    if ($rewriteKeys -match '[\p{Cc}]') { throw 'A Git URL rewrite contains control characters.' }

    # Resolve the proposed URLs with Git in the current repository, without writing a remote.
    $remote = 'gitswapping-preview-' + [guid]::NewGuid().ToString('N')
    $arguments = @('-c', "remote.$remote.url=$newFetch")
    if ($newPush) { $arguments += '-c', "remote.$remote.pushurl=$newPush" }
    $lines = Invoke-ProfileGit ($arguments + @('remote', '--verbose'))
    $entries = $lines | Where-Object { $_ -cmatch "^$remote\t" } | ForEach-Object { $_.Substring($remote.Length + 1) }
    $effectiveFetch = @($entries | Where-Object { $_.EndsWith(' (fetch)') } | ForEach-Object { $_.Substring(0, $_.Length - 8) })
    $effectivePush = @($entries | Where-Object { $_.EndsWith(' (push)') } | ForEach-Object { $_.Substring(0, $_.Length - 7) })
    foreach ($urls in @($effectiveFetch, $effectivePush)) {
        if ($urls.Count -ne 1) { throw 'The proposed origin does not resolve to one fetch and one push URL.' }
        $resolved = Get-ProfileRemote $urls[0]
        try { Assert-ProfileDestination $resolved $Account $Origin.Repo }
        catch { throw "A Git URL rewrite would change the proposed origin destination. $($_.Exception.Message)" }
        if ($resolved.Account -ne $Account) {
            throw "A Git URL rewrite would change the username in the proposed origin. Review insteadOf and pushInsteadOf."
        }
    }
    [pscustomobject]@{ Fetch = $effectiveFetch[0]; Push = $effectivePush[0] }
}
