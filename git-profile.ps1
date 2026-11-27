#requires -Version 5.1

function git-profile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('list', 'add', 'edit', 'remove', 'current', 'use', 'check', 'status', 'audit', 'help')]
        [string]$Action = 'help',

        [Parameter(Position = 1)]
        [string]$Profile,

        [switch]$Auto
    )

    if ($Auto -and ($Action -ne 'use' -or $PSBoundParameters.ContainsKey('Profile'))) {
        throw 'Use -Auto with git-profile use and omit the profile label.'
    }

    if ($Action -eq 'help') {
        Write-Host 'Git Swapping (development)' -ForegroundColor Cyan
        Write-Host 'Usage: git-profile list | current | use PROFILE | use -Auto | check | status'
        Write-Host 'Audit repositories: git-profile audit [FOLDER]'
        Write-Host 'Preview: git-profile use PROFILE -WhatIf | use -Auto -WhatIf'
        Write-Host 'Manage profiles: git-profile add PROFILE | edit PROFILE | remove PROFILE'
        return
    }

    $configPath = Join-Path $PSScriptRoot 'profiles.psd1'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "profiles.psd1 is missing. Run install.ps1 from $PSScriptRoot."
    }
    if ($Action -in @('add', 'edit', 'remove')) {
        if ($PSCmdlet.ShouldProcess("profile '$Profile' in $configPath", $Action)) {
            & (Join-Path $PSScriptRoot 'internal/Update-Profiles.ps1') -Action $Action -Label $Profile -Path $configPath
        }
        return
    }
    . (Join-Path $PSScriptRoot 'internal/ProfileFiles.ps1')
    $profiles = (Read-ProfileFile $configPath).Profiles
    & (Join-Path $PSScriptRoot 'internal/Assert-Profiles.ps1') $profiles

    if (-not $profiles.psbase.Count) {
        $message = 'No profiles are configured. Run git-profile add PROFILE.'
        if ($Action -ne 'list') { throw $message }
        Write-Host $message
        return
    }
    if ($Action -eq 'list') {
        Write-Host 'AVAILABLE PROFILES' -ForegroundColor Cyan
        foreach ($key in ($profiles.psbase.Keys | Sort-Object)) {
            $p = $profiles[$key]
            Write-Host ''
            Write-Host "Profile : $key" -ForegroundColor Yellow
            Write-Host "Name    : $($p.Name)"
            Write-Host "Email   : $($p.Email)"
            Write-Host "GitHub  : $($p.GitHub)"
        }
        return
    }

    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCommand) { throw 'Git was not found on PATH.' }
    $gitExecutable = $gitCommand.Source
    . (Join-Path $PSScriptRoot 'internal/GitConfig.ps1')

    if ($Action -eq 'use' -and -not $Auto -and (-not $Profile -or -not $profiles.ContainsKey($Profile))) {
        throw 'Profile not found. Run git-profile list.'
    }
    function Invoke-RepositoryProfile {
        param($AuditResult)

        try { $inWorkTree, $prefix = Invoke-ProfileGit @('rev-parse', '--is-inside-work-tree', '--show-prefix') }
        catch { $inWorkTree = $false }
        if ($inWorkTree -ne 'true') {
            if ($AuditResult) { $AuditResult.NextAction = 'Run git rev-parse --show-toplevel in this folder to inspect the Git diagnostic.' }
            throw 'Run this command inside a Git working tree.'
        }
        if ($AuditResult -and $prefix) {
            $AuditResult.NextAction = 'Check the .git entry in this folder against git rev-parse --show-toplevel.'
            throw 'Git resolved a different working tree for this folder.'
        }
        if ($Action -eq 'use') {
            $gitConfigPath = Get-ProfileConfigPath
            $originalConfig = [IO.File]::ReadAllBytes($gitConfigPath)
        }

        $name = Invoke-ProfileGit @('config', '--local', '--get', 'user.name') -AllowMissing
        $email = Invoke-ProfileGit @('config', '--local', '--get', 'user.email') -AllowMissing
        $rawFetch = @(Get-ProfileGitValues @('config', '--null', '--get-all', 'remote.origin.url'))
        $rawPush = @(Get-ProfileGitValues @('config', '--null', '--get-all', 'remote.origin.pushurl'))
        if ($rawFetch.Count -ne 1 -or $rawPush.Count -gt 1) {
            if ($AuditResult) { $AuditResult.NextAction = 'Configure one fetch URL and at most one push URL for origin.' }
            throw 'Configure origin with one fetch URL and at most one explicit push URL.'
        }
        $origin = Get-ProfileRemote $rawFetch[0]
        $expectedProfile = $profiles.psbase.Keys | Where-Object { $profiles[$_].GitHub -eq $origin.Owner }
        if ($AuditResult) { $AuditResult.Profile = $expectedProfile }
        $fetch = @(Invoke-ProfileGit @('remote', 'get-url', '--all', 'origin'))
        $push = @(Invoke-ProfileGit @('remote', 'get-url', '--push', '--all', 'origin'))
        if ($fetch.Count -ne 1 -or $push.Count -ne 1) {
            if ($AuditResult) { $AuditResult.NextAction = 'Review the effective fetch and push URLs for origin.' }
            throw 'This alpha requires exactly one effective fetch URL and one effective push URL.'
        }

        $parsed = @(foreach ($url in ($rawFetch + $rawPush + $fetch + $push)) { ,(Get-ProfileRemote $url) })
        if ($Action -in @('current', 'status')) {
            $matched = @($profiles.psbase.Keys | Where-Object { $name -ceq $profiles[$_].Name -and $email -ceq $profiles[$_].Email })
            $matchedProfile = if ($matched -contains $expectedProfile) { $expectedProfile } elseif ($matched.Count -eq 1) { $matched[0] }
            $safeFetch = if (Get-ProfileRemote $fetch[0]) { $fetch[0] } else { '[unsupported URL hidden]' }
            $safePush = if (Get-ProfileRemote $push[0]) { $push[0] } else { '[unsupported URL hidden]' }
            Write-Host 'LOCAL REPOSITORY CONFIGURATION' -ForegroundColor Cyan
            Write-Host "Name   : $name"
            Write-Host "Email  : $email"
            Write-Host "Origin fetch : $safeFetch"
            Write-Host "Origin push  : $safePush"
            Write-Host "Profile : $(if ($matchedProfile) { $matchedProfile } else { 'no match' })"
            if ($Action -eq 'current') { return }
            Write-Host "Expected profile : $(if ($expectedProfile) { $expectedProfile } else { 'no match' })"
        }

        if ($Action -eq 'use') {
            if (-not $origin) { Assert-ProfileDestination $origin }
            if ($Auto) {
                if (-not $expectedProfile) {
                    throw "No profile is configured for owner '$($origin.Owner)'. Run git-profile list or add a profile."
                }
                $Profile = $expectedProfile
            }
            $p = $profiles[$Profile]
            foreach ($remote in $parsed) { Assert-ProfileDestination $remote $p.GitHub $origin.Repo }
            if ($Auto -and (Get-ProfilePushRemote).Value -cne 'origin') {
                throw 'Automatic selection requires origin as the default push remote. Run git-profile status to find the overriding setting.'
            }

            $planned = Get-ProfileUsePlan $gitConfigPath $rawFetch $rawPush $origin $p
            $settings = $planned.Settings
            if ($WhatIfPreference) {
                Write-Host "Profile : $Profile"
                Write-Host "Name    : $name -> $($p.Name)"
                Write-Host "Email   : $email -> $($p.Email)"
                Write-Host "Origin fetch : $($fetch[0]) -> $($planned.Fetch)"
                Write-Host "Origin push  : $($push[0]) -> $($planned.Push)"
            }
            if (-not $PSCmdlet.ShouldProcess($gitConfigPath, "Apply profile '$Profile'")) { return }

            $lockPath = $gitConfigPath + '.lock'
            $ownsLock = $false
            try {
                $stream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $ownsLock = $true
                try {
                    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($gitConfigPath)) -ne [Convert]::ToBase64String($originalConfig)) {
                        throw 'The configuration changed during validation. Run the command again.'
                    }
                    $stream.Write($originalConfig, 0, $originalConfig.Length)
                }
                finally { $stream.Dispose() }

                foreach ($key in $settings.Keys) {
                    $null = Invoke-ProfileGit @('config', '--file', $lockPath, '--', $key, $settings[$key])
                }
                $null = Test-ProfileUrls -Settings $settings -Fetch $rawFetch[0] -Push $rawPush[0] -Origin $origin -Account $p.GitHub
                [IO.File]::Replace($lockPath, $gitConfigPath, [NullString]::Value)
                $ownsLock = $false
            }
            finally {
                if ($ownsLock -and (Test-Path -LiteralPath $lockPath)) {
                    [IO.File]::Delete($lockPath)
                }
            }
            Write-Host "PROFILE CONFIGURED: $Profile" -ForegroundColor Green
            Write-Host "Name   : $($p.Name)"
            Write-Host "Email  : $($p.Email)"
            Write-Host "GitHub : $($p.GitHub)"
            return
        }

        $issues = [Collections.Generic.List[string]]::new()
        $nextAction = ''
        $needsProfile = $false
        if (-not $origin) {
            $nextAction = 'Review origin and configure a GitHub HTTPS URL.'
            $issues.Add('Configure origin with a GitHub HTTPS URL without credentials, query strings, or fragments.')
        }
        elseif (-not $expectedProfile) {
            $nextAction = "Check the owner of origin and the saved profiles with git-profile list."
            $issues.Add("No profile is configured for owner '$($origin.Owner)'. Run git-profile list or add a profile.")
        }

        $pushSetting = Get-ProfilePushRemote
        if ($pushSetting.Value -cne 'origin') {
            if (-not $nextAction) { $nextAction = "Review $($pushSetting.Source) before pushing." }
            $destination = 'a destination without a configured remote'
            if ((Invoke-ProfileGit @('remote')) -ccontains $pushSetting.Value -and $pushSetting.Value -match '\A[\p{L}\p{N}_.\-/]+\z') {
                $destination = "remote '$($pushSetting.Value)'"
            }
            $issues.Add("Running git push without arguments selects $destination because of $($pushSetting.Source). Set that key to origin or remove the override.")
        }
        elseif ($Action -eq 'status') { Write-Host 'Default push remote : origin' }

        $p = if ($expectedProfile) { $profiles[$expectedProfile] }
        if ($p) {
            $applyHint = if (-not $AuditResult) { " Run git-profile use $expectedProfile." }
            foreach ($remote in $parsed) {
                try {
                    Assert-ProfileDestination $remote $p.GitHub $origin.Repo
                    if ($remote.Account -ne $p.GitHub) {
                        $needsProfile = $true
                        $issues.Add("The username in an origin URL does not match '$($p.GitHub)'.$applyHint")
                    }
                }
                catch {
                    if (-not $nextAction) { $nextAction = 'Review the fetch and push destinations for origin, including URL rewrites.' }
                    $issues.Add($_.Exception.Message)
                }
            }
            if ($name -cne $p.Name -or $email -cne $p.Email) {
                $needsProfile = $true
                $issues.Add("The local identity differs from profile '$expectedProfile'.$applyHint")
            }
            foreach ($field in @('name', 'email')) {
                $setting = Get-ProfileGitSetting "user.$field"
                if ($setting -and $setting.Value -cne $p[$field]) {
                    $issues.Add("Effective user.$field differs from profile '$expectedProfile'. Review $($setting.Source).")
                    if ($AuditResult -and -not $nextAction) {
                        $overridesLocal = $setting.Scope -in @('worktree', 'command')
                        if ($setting.Scope -eq 'local') {
                            $direct = Invoke-ProfileGit @('config', '--local', '--no-includes', '--null', '--show-origin', '--get', "user.$field") -Raw -AllowMissing
                            $overridesLocal = -not $direct -or $direct.Split([char]0)[0] -cne $setting.Origin
                        }
                        if ($overridesLocal) { $nextAction = "Review $($setting.Source)." }
                    }
                }
            }
        }

        foreach ($role in @('AUTHOR', 'COMMITTER')) {
            try { $identity = Invoke-ProfileGit @('var', "GIT_$($role)_IDENT") }
            catch { $identity = '' }
            if ($identity -match '\A(?<Name>.*) <(?<Email>[^<>]+)> \d+ [+-]\d{4}\z') {
                $actual = @{ name = $Matches.Name; email = $Matches.Email }
                if ($Action -eq 'status') { Write-Host "Effective $role : $($actual.name) <$($actual.email)>" }
                if ($p) {
                    foreach ($field in @('name', 'email')) {
                        if ($actual[$field] -cne $p[$field]) {
                            $source = Get-ProfileIdentitySource $role $field
                            $issues.Add("Effective $role $field differs from profile '$expectedProfile'. Review $($source.Source).")
                            if ($source.OverridesUser -and -not $nextAction) { $nextAction = "Review $($source.Source)." }
                        }
                    }
                }
            }
            else {
                $issues.Add("Git could not resolve the effective $role identity. Check the configured name and email.")
                if ($AuditResult -and $p -and -not $nextAction) {
                    foreach ($field in @('name', 'email')) {
                        $source = Get-ProfileIdentitySource $role $field
                        if ($source.OverridesUser -and $source.Value -cne $p[$field]) {
                            $nextAction = "Review $($source.Source)."
                            break
                        }
                    }
                    if (-not $nextAction -and -not $needsProfile) { $nextAction = "Review the effective $role identity with git-profile status." }
                }
            }
        }

        if ($issues.Count) {
            if ($AuditResult) {
                if (-not $nextAction -and $needsProfile) {
                    try {
                        $null = Get-ProfileUsePlan (Get-ProfileConfigPath) $rawFetch $rawPush $origin $p
                        $nextAction = 'git-profile use -Auto -WhatIf'
                    }
                    catch {
                        $issues.Add($_.Exception.Message)
                        $nextAction = 'Inspect the local Git configuration and origin URL rules.'
                    }
                }
                $AuditResult.NextAction = $nextAction
            }
            throw (($issues | Select-Object -Unique) -join [Environment]::NewLine)
        }
        if ($AuditResult) { return }
        Write-Host "OK  Profile : $expectedProfile" -ForegroundColor Green
        Write-Host "OK  GitHub  : $($p.GitHub)" -ForegroundColor Green
        Write-Host "OK  Name    : $name" -ForegroundColor Green
        Write-Host "OK  Email   : $email" -ForegroundColor Green
        Write-Host "OK  Origin fetch : $($fetch[0])" -ForegroundColor Green
        Write-Host "OK  Origin push  : $($push[0])" -ForegroundColor Green
        Write-Host 'Configuration checks passed. Verify authentication and remote permissions separately.'
    }

    if ($Action -ne 'audit') {
        Invoke-RepositoryProfile
        return
    }

    if ($env:GIT_DIR -or $env:GIT_WORK_TREE -or $env:GIT_COMMON_DIR) {
        throw 'Clear GIT_DIR, GIT_WORK_TREE, and GIT_COMMON_DIR before auditing multiple repositories.'
    }
    $folder = if ($PSBoundParameters.ContainsKey('Profile')) { $Profile } else { '.' }
    if (-not $folder) { throw 'Provide a folder to audit.' }
    $root = Get-Item -LiteralPath $folder -Force -ErrorAction Stop
    if ($root -isnot [IO.DirectoryInfo]) { throw 'Provide a filesystem folder to audit.' }

    $found = $false
    Get-ProfileRepositoryPaths $root.FullName | ForEach-Object {
        $found = $true
        $row = [pscustomobject]@{
            Repository = $_
            Profile = $null
            Result = 'OK'
            Reason = ''
            NextAction = ''
        }
        try {
            Push-Location -LiteralPath $row.Repository -ErrorAction Stop
            try { Invoke-RepositoryProfile -AuditResult $row }
            finally { Pop-Location }
        }
        catch {
            $row.Result = 'Review'
            $row.Reason = $_.Exception.Message -replace '\r?\n', '; '
            if (-not $row.NextAction) { $row.NextAction = 'Run git-profile status in this working tree and inspect the reported error.' }
        }
        $display = [Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', [string[]]@('Repository', 'Profile', 'Result', 'NextAction'))
        Add-Member -InputObject $row -MemberType MemberSet -Name PSStandardMembers -Value ([Management.Automation.PSMemberInfo[]]@($display))
        $row
    }
    if (-not $found) { Write-Host 'No Git working trees found.' }
}
