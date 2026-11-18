#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempParent ('git-profile-tests-' + [guid]::NewGuid().ToString('N'))
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
    Assert-True $failed 'Se esperaba un error y el comando termino sin fallar.'
}
function Test-Case([string]$Name, [scriptblock]$Command) {
    & $Command
    $script:passed++
    Write-Host "PASS $Name" -ForegroundColor Green
}

Push-Location
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:GIT_CONFIG_GLOBAL = Join-Path $testRoot 'empty.gitconfig'
    [IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, '')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'git-profile.ps1') -Destination $testRoot
    . (Join-Path $testRoot 'git-profile.ps1')
    Set-Location -LiteralPath $testRoot
    Test-Case 'help works without configuration' { git-profile help 6>$null }
    Test-Case 'missing configuration fails' { Assert-Fails { git-profile list } }

    $fixture = @'
@{
    personal = @{ Name = 'Personal Example'; Email = 'personal@example.com'; GitHub = 'personal-user' }
    unsa = @{ Name = 'University Example'; Email = 'university@example.com'; GitHub = 'university-user' }
}
'@
    $fixturePath = Join-Path $testRoot 'profiles.psd1'
    [IO.File]::WriteAllText($fixturePath, $fixture)
    Test-Case 'list works outside repositories' { git-profile list 6>$null }
    Test-Case 'use outside a repository fails' { Assert-Fails { git-profile use personal } }
    Test-Case 'unknown profile fails' { Assert-Fails { git-profile use unknown } }
    Test-Case 'missing profile fails' { Assert-Fails { git-profile use } }

    Test-Case 'personal profile and check' {
        New-TestRepo
        $null = Invoke-TestGit @('config', '--local', 'core.ignorecase', 'true')
        git-profile use personal 6>$null
        git-profile check 6>$null
        Assert-True ((git config --local user.email) -eq 'personal@example.com') 'Email incorrecto.'
        Assert-True ((git remote get-url origin) -eq 'https://personal-user@github.com/personal-user/demo.git') 'URL incorrecta.'
        Assert-True ((git config --local core.ignorecase) -eq 'true') 'Se perdio una configuracion ajena.'
    }
    Test-Case 'repeat is idempotent' {
        $before = Get-ConfigSnapshot
        git-profile use personal 6>$null
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'La segunda ejecucion cambio la configuracion.'
    }
    Test-Case 'current and status' {
        git-profile current 6>$null
        $status = (git-profile status 6>&1) -join "`n"
        Assert-True ($status -match 'Remoto de git push : origin') 'Status no muestra el remoto predeterminado.'
    }
    Test-Case 'default push remote follows Git precedence even on an unborn branch' {
        New-TestRepo
        git-profile use personal 6>$null
        $null = Invoke-TestGit @('symbolic-ref', 'HEAD', 'refs/heads/topic')
        $null = Invoke-TestGit @('remote', 'add', 'upstream', 'https://github.com/personal-user/demo.git')
        $null = Invoke-TestGit @('remote', 'add', 'publish', 'https://github.com/university-user/demo.git')

        $null = Invoke-TestGit @('config', '--local', 'branch.topic.remote', 'upstream')
        Assert-Fails { git-profile check } "remoto 'upstream'.*branch\.topic\.remote"
        $null = Invoke-TestGit @('config', '--local', 'remote.pushDefault', 'publish')
        Assert-Fails { git-profile check } "remoto 'publish'.*remote\.pushDefault"
        $null = Invoke-TestGit @('config', '--local', 'branch.topic.pushRemote', 'upstream')
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile status 6>$null } "remoto 'upstream'.*branch\.topic\.pushRemote"
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'Status cambio el remoto de envio.'
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
        Assert-Fails { git-profile check } "remoto 'publish'.*remote\.pushDefault"
        $null = Invoke-TestGit @('config', '--local', '--unset', 'remote.pushDefault')
        git-profile check 6>$null
    }
    Test-Case 'direct push destination is flagged without printing its URL' {
        New-TestRepo
        git-profile use personal 6>$null
        $null = Invoke-TestGit @('config', '--local', 'remote.pushDefault', 'https://user:example-token@github.com/university-user/demo.git')
        Assert-Fails { git-profile check } '^(?!.*example-token).*destino sin remoto registrado.*remote\.pushDefault'
    }
    Test-Case 'reported push override agrees with a local Git dry run' {
        New-TestRepo
        git-profile use personal 6>$null
        $branch = 'edici' + [char]0xF3 + 'n'
        $null = Invoke-TestGit @('symbolic-ref', 'HEAD', "refs/heads/$branch")
        $destination = Join-Path $testRoot 'push-destination.git'
        $null = Invoke-TestGit @('init', '--quiet', '--bare', '--template=', $destination)
        $null = Invoke-TestGit @('remote', 'add', 'publish', $destination)
        $null = Invoke-TestGit @('config', '--local', "branch.$branch.pushRemote", 'publish')
        $null = Invoke-TestGit @('config', '--local', 'push.default', 'current')
        $null = Invoke-TestGit @('commit', '--quiet', '--allow-empty', '-m', 'Local push fixture')

        $pushOutput = Invoke-TestGit @('-c', 'protocol.allow=never', '-c', 'protocol.file.allow=always', 'push', '--dry-run', '--porcelain')
        Assert-True (($pushOutput -join "`n") -match 'To .+push-destination\.git') 'Git no selecciono el destino de prueba.'

        $consoleEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850)
            Assert-Fails { git-profile check } "remoto 'publish'.*pushRemote"
            Assert-True ([Console]::OutputEncoding.CodePage -eq 850) 'Check cambio la codificacion de la consola.'
        }
        finally { [Console]::OutputEncoding = $consoleEncoding }
    }
    Test-Case 'university profile' {
        New-TestRepo 'https://github.com/university-user/demo.git'
        git-profile use unsa 6>$null
        git-profile check 6>$null
        Assert-True ((git config --local user.name) -eq 'University Example') 'Nombre incorrecto.'
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
        Assert-True ((git remote get-url --push origin) -eq 'https://personal-user@github.com/personal-user/demo.git') 'Push conserva otra cuenta.'
    }
    Test-Case 'wrong owner cannot be assigned' {
        New-TestRepo 'https://github.com/university-user/demo.git'
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile use personal }
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'Se modifico un repositorio de otra cuenta.'
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
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'Se modifico la configuracion antes de rechazar push.'
    }
    foreach ($url in @('', 'git@github.com:personal-user/demo.git', 'https://gitlab.com/personal-user/demo.git', 'https://user:secret@github.com/personal-user/demo.git')) {
        Test-Case 'missing or unsupported origin leaves config intact' {
            New-TestRepo $url
            $before = Get-ConfigSnapshot
            Assert-Fails { git-profile use personal }
            Assert-True ((Get-ConfigSnapshot) -eq $before) 'Se modifico un origin no compatible.'
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
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'Se modifico una configuracion bloqueada.'
        Assert-True ((Get-Content -LiteralPath '.git/config.lock' -Raw) -eq 'other process') 'Se elimino un bloqueo ajeno.'
    }
    Test-Case 'failed staged write leaves no partial identity or owned lock' {
        New-TestRepo
        $null = Invoke-TestGit @('config', '--local', '--add', 'user.email', 'one@example.com')
        $null = Invoke-TestGit @('config', '--local', '--add', 'user.email', 'two@example.com')
        $before = Get-ConfigSnapshot
        Assert-Fails { git-profile use personal }
        Assert-True ((Get-ConfigSnapshot) -eq $before) 'Quedo una configuracion parcial.'
        Assert-True (-not (Test-Path -LiteralPath '.git/config.lock')) 'Quedo un bloqueo propio.'
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
        Assert-Fails { git-profile check }
    }
    Test-Case 'check detects environment override' {
        New-TestRepo
        git-profile use personal 6>$null
        $env:GIT_COMMITTER_EMAIL = 'override@example.com'
        try { Assert-Fails { git-profile check } }
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
            throw 'Ruta de limpieza fuera del directorio temporal de pruebas.'
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
