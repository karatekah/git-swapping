#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$gitVersion = git --version
if ($gitVersion -notmatch '^git version (\d+\.\d+)' -or [version]$Matches[1] -lt [version]'2.32') {
    throw 'The isolated test suite requires Git 2.32 or later.'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempParent ('git-profile-tests-' + [guid]::NewGuid().ToString('N'))
$originalGlobalFunction = ${function:global:git-profile}
$savedEnvironment = @{}
$environmentNames = @(Get-ChildItem Env: | Where-Object { $_.Name -like 'GIT_*' } | ForEach-Object { $_.Name }) + @('EMAIL')
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
$script:passed = 0

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}
function Invoke-TestGit([string[]]$GitArguments) {
    $result = @(& git @GitArguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ($result -join "`n") }
    $result
}
function New-TestRepo([string]$Remote = 'https://github.com/personal-user/demo.git') {
    $repoPath = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
    $null = Invoke-TestGit @('init', '--quiet', '--template=', $repoPath)
    Set-Location -LiteralPath $repoPath
    if ($Remote) { $null = Invoke-TestGit @('remote', 'add', 'origin', $Remote) }
}
function Get-ConfigSnapshot {
    [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path (Get-Location).Path '.git/config')))
}
function Assert-Fails([scriptblock]$Command, [string]$ExpectedMessage) {
    $failed = $false
    try { & $Command | Out-Null }
    catch {
        if ($ExpectedMessage -and $_.Exception.Message -notmatch $ExpectedMessage) { throw }
        $failed = $true
    }
    Assert-True $failed 'Expected the command to fail, but it succeeded.'
}
function Test-Case([string]$Name, [scriptblock]$Command) {
    & $Command
    $script:passed++
    Write-Host "PASS $Name" -ForegroundColor Green
}
function Invoke-WithAnswers([scriptblock]$Command, [string[]]$Answers = @()) {
    $inputs = [Collections.Generic.Queue[string]]::new()
    foreach ($answer in $Answers) { $inputs.Enqueue($answer) }
    function Read-Host([string]$Prompt) {
        if (-not $inputs.Count) { throw "Unexpected prompt: $Prompt" }
        $inputs.Dequeue()
    }
    & $Command
    Assert-True ($inputs.Count -eq 0) 'The command did not use all test answers.'
}

function Invoke-TestInstaller {
    param([string[]]$Answers = @(), [string]$ShellProfile = $installerProfilePath)

    $PROFILE = [pscustomobject]@{
        CurrentUserAllHosts = $allHostsProfilePath
        CurrentUserCurrentHost = $ShellProfile
    }
    Invoke-WithAnswers { & (Join-Path $installerRoot 'install.ps1') 6>$null } $Answers
}

Push-Location
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:GIT_CONFIG_GLOBAL = Join-Path $testRoot 'empty.gitconfig'
    [IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, '')
    $installerRoot = Join-Path $testRoot "Installer's clone"
    $installerProfilePath = Join-Path $testRoot 'PowerShell\Microsoft.PowerShell_profile.ps1'
    $allHostsProfilePath = Join-Path $testRoot 'PowerShell\profile.ps1'
    $installerConfig = Join-Path $installerRoot 'profiles.psd1'
    $null = New-Item -ItemType Directory -Path $installerRoot
    foreach ($file in @('git-profile.ps1', 'install.ps1', 'internal')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $installerRoot -Recurse
    }

    Test-Case 'installer rejects invalid answers before writing configuration' {
        Assert-Fails { Invoke-TestInstaller @('personal', 'Test Name', 'bad-email', 'personal-user', '') } 'Invalid profile'
        Assert-True (-not (Test-Path -LiteralPath $installerConfig)) 'Invalid accounts were saved.'
        Assert-True (-not (Test-Path -LiteralPath $installerProfilePath)) 'An incomplete install registered a loader.'
    }
    Test-Case 'installer saves accounts and registers the command in both sessions' {
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $installerProfilePath))
        $existingProfile = "# Existing PowerShell settings`r`n"
        [IO.File]::WriteAllText($installerProfilePath, $existingProfile, [Text.Encoding]::Unicode)
        $author = "O'Connor " + [char]0xE1
        Invoke-TestInstaller @('personal', $author, 'personal@example.com', 'personal-user', 'y', 'school', 'School Example', 'school@example.com', 'school-user', '')

        $profiles = Import-PowerShellDataFile -LiteralPath $installerConfig
        Assert-True ($profiles.Count -eq 2 -and $profiles.personal.Name -ceq $author) 'The profiles did not round-trip through the data file.'
        $expectedScript = Join-Path $installerRoot 'git-profile.ps1'
        Assert-True ((Get-Command git-profile).ScriptBlock.File -eq $expectedScript) 'The command is missing from the current session.'
        & {
            function git-profile { throw 'The loader did not replace the placeholder command.' }
            . $installerProfilePath
            git-profile list 6>$null
            Assert-True ((Get-Command git-profile).ScriptBlock.File -eq $expectedScript) 'The PowerShell profile did not load the command.'
        }
        Assert-True (([IO.File]::ReadAllText($installerProfilePath)).StartsWith($existingProfile)) 'Existing PowerShell settings were changed.'
        $backup = @(Get-ChildItem -LiteralPath (Split-Path -Parent $installerProfilePath) -Filter '*.bak')
        Assert-True ($backup.Count -eq 1 -and [IO.File]::ReadAllText($backup[0].FullName) -ceq $existingProfile) 'The installer did not back up the previous profile.'
    }
    Test-Case 'installer reruns preserve the profile and account files' {
        $beforeProfile = (Get-FileHash -LiteralPath $installerProfilePath).Hash
        $beforeConfig = (Get-FileHash -LiteralPath $installerConfig).Hash
        Invoke-TestInstaller
        Assert-True ((Get-FileHash -LiteralPath $installerProfilePath).Hash -eq $beforeProfile) 'A second install changed the PowerShell profile.'
        Assert-True ((Get-FileHash -LiteralPath $installerConfig).Hash -eq $beforeConfig) 'A second install changed the accounts.'
    }
    Test-Case 'installer creates and refreshes a managed PowerShell profile' {
        $newHost = Join-Path $testRoot 'NewHost\Microsoft.PowerShell_profile.ps1'
        Invoke-TestInstaller -ShellProfile $newHost
        Assert-True (Test-Path -LiteralPath $newHost -PathType Leaf) 'The installer did not create the host profile.'
        $currentLoader = [IO.File]::ReadAllText($newHost)
        [IO.File]::WriteAllText($newHost, $currentLoader.Replace('git-profile.ps1', 'previous-location.ps1'), [Text.Encoding]::UTF8)
        Invoke-TestInstaller -ShellProfile $newHost
        Assert-True ([IO.File]::ReadAllText($newHost) -ceq $currentLoader) 'The installer appended a second loader after the path changed.'
    }
    Test-Case 'installer recognizes the earlier manual loader' {
        $manualScript = (Join-Path $installerRoot 'git-profile.ps1').Replace("'", "''")
        $manualLoader = "if (Test-Path -LiteralPath '$manualScript') { . '$manualScript' }"
        [IO.File]::WriteAllText($allHostsProfilePath, $manualLoader)
        $anotherHost = Join-Path $testRoot 'PowerShell\AnotherHost_profile.ps1'
        Invoke-TestInstaller -ShellProfile $anotherHost
        Assert-True (-not (Test-Path -LiteralPath $anotherHost)) 'The installer duplicated the manual loader.'
        Assert-True ([IO.File]::ReadAllText($allHostsProfilePath) -ceq $manualLoader) 'The installer modified the manual loader.'
    }

    foreach ($file in @('git-profile.ps1', 'internal')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $testRoot -Recurse
    }
    . (Join-Path $testRoot 'git-profile.ps1')
    Set-Location -LiteralPath $testRoot
    Test-Case 'help works without configuration' {
        $helpOutput = (git-profile help 6>&1) -join "`n"
        Assert-True ($helpOutput -match 'Usage: git-profile list') 'Help does not show the usage in English.'
    }
    Test-Case 'missing configuration fails' {
        Assert-Fails { git-profile list } 'profiles\.psd1 is missing'
    }

    $fixturePath = Join-Path $testRoot 'profiles.psd1'
    $inlineProfile = "@{ personal = @{ Name = 'Personal Example'; Email = 'personal@example.com'; GitHub = 'personal-user'; Extra = 'keep me' }; <# local note #> }"
    [IO.File]::WriteAllText($fixturePath, $inlineProfile)
    Test-Case 'add and edit saved profiles outside a repository' {
        Invoke-WithAnswers { git-profile add work 6>$null } @("D'Angelo", 'work@example.com', 'work-user')
        $stored = Import-PowerShellDataFile -LiteralPath $fixturePath
        Assert-True ($stored.work.Name -ceq "D'Angelo") 'Add did not store the quoted name.'
        Invoke-WithAnswers { git-profile edit personal 6>$null } @('Changed Name', '', 'updated-personal')
        $stored = Import-PowerShellDataFile -LiteralPath $fixturePath
        Assert-True ($stored.personal.Name -ceq 'Changed Name' -and $stored.personal.GitHub -ceq 'updated-personal') 'Edit did not store the new values.'
        Assert-True ($stored.personal.Email -ceq 'personal@example.com') 'Edit overwrote a field skipped by pressing Enter.'
        Assert-True ($stored.personal.Extra -ceq 'keep me' -and [IO.File]::ReadAllText($fixturePath).Contains('<# local note #>')) 'Edit removed extra data or a comment.'
        $listOutput = (git-profile list 6>&1) -join "`n"
        Assert-True ($listOutput -match 'Profile : work' -and $listOutput -match 'updated-personal') 'List did not show the saved changes.'
    }
    Test-Case 'invalid profile changes leave the file intact' {
        $before = (Get-FileHash -LiteralPath $fixturePath).Hash
        Assert-Fails { Invoke-WithAnswers { git-profile add WORK 6>$null } } 'already exists'
        Assert-Fails { Invoke-WithAnswers { git-profile edit unknown 6>$null } } 'was not found'
        Assert-Fails { Invoke-WithAnswers { git-profile add extra 6>$null } @('Extra', 'not-an-email', 'extra-user') } 'Invalid profile'
        Assert-Fails { Invoke-WithAnswers { git-profile edit work 6>$null } @('', '', 'updated-personal') } 'duplicate GitHub account'
        Invoke-WithAnswers { git-profile edit work 6>$null } @('', '', '')
        Assert-True ((Get-FileHash -LiteralPath $fixturePath).Hash -eq $before) 'An invalid or empty edit changed the file.'
    }
    Test-Case 'remove can be cancelled and the last profile can be replaced' {
        $before = (Get-FileHash -LiteralPath $fixturePath).Hash
        Invoke-WithAnswers { git-profile remove personal 6>$null } @('')
        Assert-True ((Get-FileHash -LiteralPath $fixturePath).Hash -eq $before) 'Cancelling removal changed the file.'
        Invoke-WithAnswers { git-profile remove personal 6>$null } @('y')
        $stored = Import-PowerShellDataFile -LiteralPath $fixturePath
        Assert-True ($stored.Count -eq 1 -and $stored.ContainsKey('work')) 'Remove did not preserve the other profile.'
        Invoke-WithAnswers { git-profile remove work 6>$null } @('yes')
        $listOutput = (git-profile list 6>&1) -join "`n"
        Assert-True ($listOutput -match 'No profiles are configured') 'List did not report the empty configuration.'
        Assert-True ([IO.File]::ReadAllText($fixturePath).Contains('<# local note #>')) 'Removing the last profile removed a comment.'
        Invoke-WithAnswers { git-profile add keys 6>$null } @('New Name', 'new@example.com', 'new-user')
        $listOutput = (git-profile list 6>&1) -join "`n"
        Assert-True ($listOutput -match 'Profile : keys') 'Add did not restore a profile to the empty configuration.'
    }
    Test-Case 'profile commands preserve changes made during a prompt' {
        $externallyUpdated = [IO.File]::ReadAllText($fixturePath) + "`r`n# Changed by another session`r`n"
        & {
            function Read-Host {
                [IO.File]::WriteAllText($fixturePath, $externallyUpdated)
                'y'
            }
            Assert-Fails { git-profile remove keys 6>$null } 'changed while you were entering data'
        }
        Assert-True ([IO.File]::ReadAllText($fixturePath) -ceq $externallyUpdated) 'The command overwrote the concurrent change.'
        Assert-True (-not (Test-Path -LiteralPath "$fixturePath.lock.bak")) 'The command left a lock behind.'
    }
    Test-Case 'editing a UTF-8 profile without a BOM preserves its accented name and comments' {
        $name = 'Jos' + [char]0xE9
        $comment = '# configuraci' + [char]0xF3 + 'n'
        $content = $comment + [Environment]::NewLine + "@{ personal = @{ Name = '$name'; Email = 'old@example.com'; GitHub = 'personal-user' } }"
        [IO.File]::WriteAllText($fixturePath, $content, [Text.UTF8Encoding]::new($false))
        $listing = (git-profile list 6>&1) -join [Environment]::NewLine
        Assert-True ($listing.Contains($name)) 'List misread the name before editing.'
        Invoke-WithAnswers { git-profile edit personal 6>$null } @('', 'new@example.com', '')
        $stored = Import-PowerShellDataFile -LiteralPath $fixturePath
        Assert-True ($stored.personal.Name -ceq $name -and $stored.personal.Email -eq 'new@example.com') 'The edit damaged the profile.'
        Assert-True ([IO.File]::ReadAllText($fixturePath).Contains($comment)) 'The edit damaged the comment.'
    }

    $fixture = @'
@{
    personal = @{ Name = 'Personal Example'; Email = 'personal@example.com'; GitHub = 'personal-user' }
    unsa = @{ Name = 'University Example'; Email = 'university@example.com'; GitHub = 'university-user' }
}
'@
    [IO.File]::WriteAllText($fixturePath, $fixture)
    Test-Case 'list works outside repositories' {
        $listOutput = (git-profile list 6>&1) -join "`n"
        Assert-True ($listOutput -match 'AVAILABLE PROFILES') 'List does not show the profiles heading.'
    }
    Test-Case 'use outside a repository fails' { Assert-Fails { git-profile use personal } }
    Test-Case 'unknown profile fails' { Assert-Fails { git-profile use unknown } }
    Test-Case 'missing profile fails' { Assert-Fails { git-profile use } }

    Test-Case 'automatic selection previews local changes without touching files' {
        New-TestRepo 'https://github.com/university-user/demo.git'
        $before = Get-ConfigSnapshot
        $profileHash = (Get-FileHash -LiteralPath $fixturePath).Hash
        $preview = (git-profile use -Auto -WhatIf 6>&1) -join [Environment]::NewLine
        Assert-True ($preview -match 'Profile : unsa' -and $preview -match 'university-user@github.com/university-user/demo\.git') 'Preview did not show the selected profile and URL.'
        $null = git-profile remove unsa -WhatIf 6>&1
        Assert-True ((Get-ConfigSnapshot) -eq $before -and -not (Test-Path -LiteralPath '.git/config.lock')) 'Preview wrote Git configuration.'
        Assert-True ((Get-FileHash -LiteralPath $fixturePath).Hash -eq $profileHash) 'Preview changed the profiles file.'
        git-profile use -Auto 6>$null
        git-profile check 6>$null
        Assert-True ((git config --local user.email) -eq 'university@example.com') 'Auto did not apply the university profile.'
    }
    Test-Case 'auto rejects an unknown owner, conflicting arguments or a different push remote' {
        New-TestRepo 'https://github.com/unknown-user/demo.git'
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile use -Auto } 'No profile is configured'
        Assert-Fails { git-profile use personal -Auto } 'omit the profile label'
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'An unassigned repository was modified.'
        New-TestRepo
        $null = Invoke-TestGit @('remote', 'add', 'upstream', 'https://github.com/university-user/demo.git')
        $null = Invoke-TestGit @('config', '--local', 'remote.pushDefault', 'upstream')
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile use -Auto } 'default push remote'
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'Auto wrote config despite a conflicting push destination.'
    }
    Test-Case 'owner disambiguates two profiles with the same commit identity' {
        $shared = $fixture.Replace('University Example', 'Personal Example').Replace('university@example.com', 'personal@example.com')
        [IO.File]::WriteAllText($fixturePath, $shared)
        try {
            foreach ($item in @(@('personal', 'personal-user'), @('unsa', 'university-user'))) {
                New-TestRepo "https://github.com/$($item[1])/demo.git"
                git-profile use -Auto 6>$null
                $status = (git-profile status 6>&1) -join [Environment]::NewLine
                Assert-True ($status -match "Expected profile : $($item[0])" -and $status -match "OK  Profile : $($item[0])") 'Status selected the wrong profile.'
            }
        }
        finally { [IO.File]::WriteAllText($fixturePath, $fixture) }
    }
    Test-Case 'use passes literal quotes, backslashes and Unicode through to Git' {
        $name = 'Jos' + [char]0xE9 + ' \"J\" \path\ Example'
        [IO.File]::WriteAllText($fixturePath, $fixture.Replace('Personal Example', $name))
        try {
            New-TestRepo
            git-profile use personal 6>$null
            git-profile check 6>$null
            $current = (git-profile current 6>&1) -join [Environment]::NewLine
            Assert-True ($current.Contains($name)) 'Git received a different author name.'
        }
        finally { [IO.File]::WriteAllText($fixturePath, $fixture) }
    }

    Test-Case 'personal profile and check' {
        New-TestRepo
        $null = Invoke-TestGit @('config', '--local', 'core.ignorecase', 'true')
        git-profile use personal 6>$null
        git-profile check 6>$null
        Assert-True ((git config --local user.email) -eq 'personal@example.com') 'The local email is incorrect.'
        Assert-True ((git remote get-url origin) -eq 'https://personal-user@github.com/personal-user/demo.git') 'The origin URL is incorrect.'
        Assert-True ((git config --local core.ignorecase) -eq 'true') 'An unrelated setting was lost.'
    }
    Test-Case 'repeat is idempotent' {
        $before = Get-ConfigSnapshot
        git-profile use personal 6>$null
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'The second run changed the configuration.'
    }
    Test-Case 'current and status' {
        git-profile current 6>$null
        $status = (git-profile status 6>&1) -join "`n"
        Assert-True ($status -match 'Default push remote : origin') 'Status does not show the default push remote.'
    }
    Test-Case 'default push remote follows Git precedence even on an unborn branch' {
        New-TestRepo
        git-profile use personal 6>$null
        $null = Invoke-TestGit @('symbolic-ref', 'HEAD', 'refs/heads/topic')
        $null = Invoke-TestGit @('remote', 'add', 'upstream', 'https://github.com/personal-user/demo.git')
        $null = Invoke-TestGit @('remote', 'add', 'publish', 'https://github.com/university-user/demo.git')

        $null = Invoke-TestGit @('config', '--local', 'branch.topic.remote', 'upstream')
        Assert-Fails { git-profile check } "remote 'upstream'.*branch\.topic\.remote"
        $null = Invoke-TestGit @('config', '--local', 'remote.pushDefault', 'publish')
        Assert-Fails { git-profile check } "remote 'publish'.*remote\.pushDefault"
        $null = Invoke-TestGit @('config', '--local', 'branch.topic.pushRemote', 'upstream')
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile status 6>$null } "remote 'upstream'.*branch\.topic\.pushRemote"
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'Status changed the push remote.'
        $null = Invoke-TestGit @('config', '--local', 'branch.topic.pushRemote', 'origin')
        git-profile check 6>$null
    }
    Test-Case 'detached HEAD uses repository push default' {
        New-TestRepo
        git-profile use personal 6>$null
        $null = Invoke-TestGit @('symbolic-ref', 'HEAD', 'refs/heads/topic')
        $null = Invoke-TestGit @('commit', '--quiet', '--allow-empty', '-m', 'Detached HEAD fixture')
        $null = Invoke-TestGit @('remote', 'add', 'publish', 'https://github.com/university-user/demo.git')
        $null = Invoke-TestGit @('config', '--local', 'branch.topic.pushRemote', 'origin')
        $null = Invoke-TestGit @('config', '--local', 'remote.pushDefault', 'publish')
        $null = Invoke-TestGit @('checkout', '--quiet', '--detach')
        Assert-Fails { git-profile check } "remote 'publish'.*remote\.pushDefault"
        $null = Invoke-TestGit @('config', '--local', '--unset', 'remote.pushDefault')
        git-profile check 6>$null
    }
    Test-Case 'direct push destination is flagged without printing its URL' {
        New-TestRepo
        git-profile use personal 6>$null
        $null = Invoke-TestGit @('config', '--local', 'remote.pushDefault', 'https://user:example-token@github.com/university-user/demo.git')
        Assert-Fails { git-profile check } '^(?!.*example-token).*destination without a configured remote.*remote\.pushDefault'
    }
    Test-Case 'reported push override agrees with a local Git dry run' {
        New-TestRepo
        git-profile use personal 6>$null
        $branch = 'caf' + [char]0xE9 + '-topic'
        $null = Invoke-TestGit @('symbolic-ref', 'HEAD', "refs/heads/$branch")
        $destination = Join-Path $testRoot 'push-destination.git'
        $null = Invoke-TestGit @('init', '--quiet', '--bare', '--template=', $destination)
        $null = Invoke-TestGit @('remote', 'add', 'publish', $destination)
        $null = Invoke-TestGit @('config', '--local', "branch.$branch.pushRemote", 'publish')
        $null = Invoke-TestGit @('config', '--local', 'push.default', 'current')
        $null = Invoke-TestGit @('commit', '--quiet', '--allow-empty', '-m', 'Local push fixture')

        $pushOutput = Invoke-TestGit @('-c', 'protocol.allow=never', '-c', 'protocol.file.allow=always', 'push', '--dry-run', '--porcelain')
        Assert-True (($pushOutput -join "`n") -match 'To .+push-destination\.git') 'Git did not select the test destination.'

        $consoleEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850)
            Assert-Fails { git-profile check } "remote 'publish'.*pushRemote"
            Assert-True ([Console]::OutputEncoding.CodePage -eq 850) 'Check changed the console encoding.'
        }
        finally { [Console]::OutputEncoding = $consoleEncoding }
    }
    Test-Case 'university profile' {
        New-TestRepo 'https://github.com/university-user/demo.git'
        git-profile use unsa 6>$null
        git-profile check 6>$null
        Assert-True ((git config --local user.name) -eq 'University Example') 'The local name is incorrect.'
    }
    Test-Case 'existing account in HTTPS is replaced' {
        New-TestRepo 'https://university-user@github.com/personal-user/demo.git'
        git-profile use personal 6>$null
        git-profile check 6>$null
    }
    Test-Case 'explicit push URL is corrected' {
        New-TestRepo
        $null = Invoke-TestGit @('config', '--local', 'remote.origin.pushurl', 'https://university-user@github.com/personal-user/demo.git')
        git-profile use personal 6>$null
        git-profile check 6>$null
        Assert-True ((git remote get-url --push origin) -eq 'https://personal-user@github.com/personal-user/demo.git') 'The push URL retained a different account.'
    }
    Test-Case 'wrong owner cannot be assigned' {
        New-TestRepo 'https://github.com/university-user/demo.git'
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile use personal }
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'A repository belonging to another account was modified.'
    }
    Test-Case 'check rejects matching username with wrong owner' {
        New-TestRepo 'https://personal-user@github.com/university-user/demo.git'
        $null = Invoke-TestGit @('config', '--local', 'user.name', 'Personal Example')
        $null = Invoke-TestGit @('config', '--local', 'user.email', 'personal@example.com')
        Assert-Fails { git-profile check }
    }
    Test-Case 'push to another repository fails before writes' {
        New-TestRepo
        $null = Invoke-TestGit @('config', '--local', 'remote.origin.pushurl', 'https://github.com/personal-user/other.git')
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile use personal }
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'The configuration changed before the push URL was rejected.'
    }
    foreach ($rule in @('insteadOf', 'pushInsteadOf')) {
        Test-Case "reject $rule rewriting the proposed origin before any writes" {
            New-TestRepo
            $null = Invoke-TestGit @('config', '--local', "url.https://personal-user@github.com/personal-user/other.git.$rule", 'https://personal-user@github.com/personal-user/demo.git')
            $before = Get-ConfigSnapshot
            Assert-Fails { git-profile use personal -WhatIf 6>$null } 'rewrite would change'
            Assert-Fails { git-profile use -Auto 6>$null } 'rewrite would change'
            Assert-True ((Get-ConfigSnapshot) -eq $before -and -not (Test-Path -LiteralPath '.git/config.lock')) 'A rewrite changed the repository configuration.'
        }
    }
    Test-Case 'remote-dependent includes are rejected before changing origin' {
        New-TestRepo
        $null = Invoke-TestGit @('config', '--local', 'includeIf.hasconfig:remote.*.url:https://personal-user@github.com/**.path', 'conditional.gitconfig')
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile use -Auto } 'configuration depends on remote URLs'
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'The remote-dependent configuration was changed.'
    }
    Test-Case 'current and status hide credentials in origin URLs and errors' {
        New-TestRepo 'https://user:example-token@github.com/personal-user/demo.git'
        $current = (git-profile current 6>&1) -join [Environment]::NewLine
        Assert-True ($current -match 'unsupported URL hidden' -and $current -notmatch 'example-token') 'Current leaked a credential.'
        $output = [Collections.Generic.List[string]]::new()
        Assert-Fails { git-profile status 6>&1 | ForEach-Object { $output.Add($_.ToString()) } } '(?s)\A(?!.*example-token).*without credentials'
        Assert-True (($output -join [Environment]::NewLine) -notmatch 'example-token') 'Status leaked a credential.'
    }
    foreach ($url in @('', 'git@github.com:personal-user/demo.git', 'https://gitlab.com/personal-user/demo.git', 'https://user:secret@github.com/personal-user/demo.git')) {
        Test-Case 'missing or unsupported origin leaves config intact' {
            New-TestRepo $url
            $before = Get-ConfigSnapshot
            Assert-Fails { git-profile use personal }
            Assert-True ((Get-ConfigSnapshot) -eq $before) 'The configuration changed despite the unsupported origin.'
        }
    }
    Test-Case 'multiple fetch URLs are rejected' {
        New-TestRepo
        $null = Invoke-TestGit @('config', '--local', '--add', 'remote.origin.url', 'https://github.com/personal-user/other.git')
        Assert-Fails { git-profile use personal }
    }
    Test-Case 'multiple push URLs are rejected' {
        New-TestRepo
        $null = Invoke-TestGit @('config', '--local', '--add', 'remote.origin.pushurl', 'https://github.com/personal-user/demo.git')
        $null = Invoke-TestGit @('config', '--local', '--add', 'remote.origin.pushurl', 'https://github.com/personal-user/other.git')
        Assert-Fails { git-profile use personal }
    }
    Test-Case 'existing lock is preserved and config stays intact' {
        New-TestRepo
        [IO.File]::WriteAllText((Join-Path (Get-Location).Path '.git/config.lock'), 'other process')
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile use personal }
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'The locked configuration was modified.'
        Assert-True ((Get-Content -LiteralPath '.git/config.lock' -Raw) -eq 'other process') 'The lock owned by another process was removed.'
    }
    Test-Case 'failed staged write leaves no partial identity or owned lock' {
        New-TestRepo
        $null = Invoke-TestGit @('config', '--local', '--add', 'user.email', 'one@example.com')
        $null = Invoke-TestGit @('config', '--local', '--add', 'user.email', 'two@example.com')
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile use personal }
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'The configuration was partially updated.'
        Assert-True (-not (Test-Path -LiteralPath '.git/config.lock')) 'The lock created by the command was left behind.'
    }
    Test-Case 'check detects wrong push account' {
        New-TestRepo
        git-profile use personal 6>$null
        $null = Invoke-TestGit @('config', '--local', 'remote.origin.pushurl', 'https://university-user@github.com/personal-user/demo.git')
        Assert-Fails { git-profile check }
    }
    Test-Case 'check detects author override' {
        New-TestRepo
        git-profile use personal 6>$null
        $null = Invoke-TestGit @('config', '--local', 'author.email', 'override@example.com')
        Assert-Fails { git-profile status 6>$null } 'author\.email \[local, file:'
    }
    Test-Case 'check detects environment override' {
        New-TestRepo
        git-profile use personal 6>$null
        $env:GIT_COMMITTER_EMAIL = 'override@example.com'
        try { Assert-Fails { git-profile check } 'GIT_COMMITTER_EMAIL' }
        finally { Remove-Item Env:GIT_COMMITTER_EMAIL }
    }
    Test-Case 'duplicate configured accounts are rejected' {
        [IO.File]::WriteAllText($fixturePath, ($fixture -replace "GitHub = 'university-user'", "GitHub = 'personal-user'"))
        try { Assert-Fails { git-profile list } }
        finally { [IO.File]::WriteAllText($fixturePath, $fixture) }
    }
    Write-Host "`n$script:passed tests passed. No network or stored credentials used." -ForegroundColor Cyan
}
finally {
    Pop-Location
    if ($originalGlobalFunction) {
        Set-Item -Path Function:global:git-profile -Value $originalGlobalFunction
    }
    else {
        Remove-Item -Path Function:global:git-profile -ErrorAction SilentlyContinue
    }
    foreach ($name in @('GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL', 'GIT_COMMITTER_EMAIL')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedRoot = (Resolve-Path -LiteralPath $testRoot).ProviderPath
        if (-not $resolvedRoot.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolvedRoot) -notmatch '^git-profile-tests-[0-9a-f]{32}$') {
            throw 'The cleanup path is outside the temporary test directory.'
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
