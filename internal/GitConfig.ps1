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

function Get-ProfileRepositoryPaths {
    param([string]$Root)

    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($Root)
    while ($pending.Count) {
        $folder = $pending.Pop()
        try {
            $children = [IO.DirectoryInfo]::new($folder).GetDirectories()
        }
        catch {
            Write-Warning ('Could not scan folder: ' + $folder)
            continue
        }
        $marker = [IO.Path]::Combine($folder, '.git')
        if ([IO.Directory]::Exists($marker) -or [IO.File]::Exists($marker)) {
            $folder
        }
        foreach ($child in $children) {
            if ($child.Name -ne '.git' -and -not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $pending.Push($child.FullName)
            }
        }
    }
}

function Get-ProfileGitSetting {
    param([string]$Key)

    $value = Invoke-ProfileGit @('config', '--null', '--show-scope', '--show-origin', '--get', $Key) -AllowMissing -Raw
    if ($null -eq $value) { return }
    $scope, $source, $setting = $value.Split([char]0)
    [pscustomobject]@{ Value = $setting[0]; Source = "$Key [$scope, $source]"; Scope = $scope; Origin = $source }
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
    if (Test-Path -LiteralPath "Env:$environmentKey") {
        return [pscustomobject]@{ Source = $environmentKey; OverridesUser = $true; Value = [Environment]::GetEnvironmentVariable($environmentKey) }
    }
    $setting = Get-ProfileGitSetting "$($Role.ToLowerInvariant()).$Field"
    if ($setting) { return [pscustomobject]@{ Source = $setting.Source; OverridesUser = $true; Value = $setting.Value } }
    $setting = Get-ProfileGitSetting "user.$Field"
    $source = if ($setting) { $setting.Source }
              elseif ($Field -eq 'email' -and (Test-Path -LiteralPath 'Env:EMAIL')) { 'EMAIL' }
              else { 'Git defaults' }
    [pscustomobject]@{ Source = $source; OverridesUser = $false }
}

function Get-ProfileConfigPath {
    $commonDir = Invoke-ProfileGit @('rev-parse', '--git-common-dir')
    $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $commonDir 'config'))
    if ((Get-Item -LiteralPath $path -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'This alpha cannot modify a linked Git config file.'
    }
    $path
}

function Get-ProfileUsePlan {
    param($ConfigPath, $RawFetch, $RawPush, $Origin, $AccountProfile)

    $localFetch = @(Get-ProfileGitValues @('config', '--file', $ConfigPath, '--null', '--get-all', 'remote.origin.url'))
    $localPush = @(Get-ProfileGitValues @('config', '--file', $ConfigPath, '--null', '--get-all', 'remote.origin.pushurl'))
    if ($localFetch.Count -ne 1 -or $localFetch[0] -cne $RawFetch[0] -or
        $localPush.Count -ne $RawPush.Count -or $localPush[0] -cne $RawPush[0]) {
        throw 'Configure origin directly in the local Git config before applying a profile.'
    }
    $account = $AccountProfile.GitHub
    $settings = [ordered]@{
        'user.name' = $AccountProfile.Name
        'user.email' = $AccountProfile.Email
        'remote.origin.url' = $RawFetch[0] -replace '^https://(?:[^@/]+@)?github\.com/', "https://$account@github.com/"
    }
    if ($RawPush.Count) {
        $settings['remote.origin.pushurl'] = $RawPush[0] -replace '^https://(?:[^@/]+@)?github\.com/', "https://$account@github.com/"
    }
    $urls = Test-ProfileUrls -Settings $settings -Fetch $RawFetch[0] -Push $RawPush[0] -Origin $Origin -Account $account
    [pscustomobject]@{ Settings = $settings; Fetch = $urls.Fetch; Push = $urls.Push }
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
