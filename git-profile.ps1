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
        $output = @(& git @GitArguments 2>&1)
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            if ($AllowMissing -and $code -eq 1) { return }
            throw "Git fallo (codigo $code): $($output -join [Environment]::NewLine)"
        }
        $output | ForEach-Object { $_.ToString() }
    }

    function Read-ProfileRemote {
        param([string]$Url)
        if ($Url -notmatch '^https://(?:(?<Account>[a-z0-9-]+)@)?github\.com/(?<Owner>[a-z0-9-]+)/(?<Repo>[a-z0-9_.-]+?)(?:\.git)?/?$') {
            throw 'Esta alfa solo admite origin HTTPS de github.com, sin claves, parametros ni fragmentos.'
        }
        [pscustomobject]@{
            Account = $Matches.Account
            Owner = $Matches.Owner
            Repo = $Matches.Repo
        }
    }

    if ($Action -eq 'help') {
        Write-Host 'git-profile v0.1.0-alpha.2' -ForegroundColor Cyan
        Write-Host 'Uso: git-profile list | current | use PERFIL | check | status'
        return
    }

    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'No se encontro Git en PATH.'
    }
    $configPath = Join-Path $PSScriptRoot 'profiles.psd1'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Falta profiles.psd1. Copia profiles.example.psd1 y configura tus cuentas en $PSScriptRoot."
    }
    $profiles = Import-PowerShellDataFile -LiteralPath $configPath -ErrorAction Stop
    if ($profiles.Count -eq 0) { throw 'No hay perfiles configurados.' }
    $accounts = @()
    foreach ($key in $profiles.Keys) {
        $p = $profiles[$key]
        if ($key -notmatch '^[a-z0-9_-]+$' -or $p -isnot [hashtable] -or
            $p.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($p.Name) -or
            $p.Email -isnot [string] -or $p.Email -notmatch '^[^\s<>@]+@[^\s<>@]+$' -or
            $p.GitHub -isnot [string] -or $p.GitHub -notmatch '^[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?$' -or
            $p.Name -match '[\r\n<>]' -or $accounts -contains $p.GitHub) {
            throw "Perfil '$key' invalido o cuenta GitHub duplicada. Revisa profiles.psd1."
        }
        $accounts += $p.GitHub
    }

    if ($Action -eq 'list') {
        Write-Host 'PERFILES DISPONIBLES' -ForegroundColor Cyan
        foreach ($key in ($profiles.Keys | Sort-Object)) {
            $p = $profiles[$key]
            Write-Host "`nPerfil : $key" -ForegroundColor Yellow
            Write-Host "Nombre : $($p.Name)`nEmail  : $($p.Email)`nGitHub : $($p.GitHub)"
        }
        return
    }
    if ($Action -eq 'use' -and ([string]::IsNullOrWhiteSpace($Profile) -or -not $profiles.ContainsKey($Profile))) {
        throw 'Perfil no encontrado. Usa: git-profile list'
    }
    if ((Invoke-ProfileGit -GitArguments @('rev-parse', '--is-inside-work-tree')) -ne 'true') {
        throw 'Entra en un repositorio de trabajo antes de ejecutar este comando.'
    }
    if ($Action -eq 'use') {
        $gitConfigPath = Invoke-ProfileGit -GitArguments @('rev-parse', '--path-format=absolute', '--git-path', 'config')
        if ((Get-Item -LiteralPath $gitConfigPath).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Esta alfa no modifica archivos config que sean enlaces.'
        }
        $originalConfig = [IO.File]::ReadAllBytes($gitConfigPath)
    }

    $name = Invoke-ProfileGit -GitArguments @('config', '--local', '--get', 'user.name') -AllowMissing
    $email = Invoke-ProfileGit -GitArguments @('config', '--local', '--get', 'user.email') -AllowMissing
    $rawFetch = @(Invoke-ProfileGit -GitArguments @('config', '--get-all', 'remote.origin.url') -AllowMissing)
    $rawPush = @(Invoke-ProfileGit -GitArguments @('config', '--get-all', 'remote.origin.pushurl') -AllowMissing)
    if ($rawFetch.Count -ne 1 -or $rawPush.Count -gt 1) {
        throw 'Se requiere origin con una URL de descarga y, como maximo, una URL de envio.'
    }
    $fetch = @(Invoke-ProfileGit -GitArguments @('remote', 'get-url', '--all', 'origin'))
    $push = @(Invoke-ProfileGit -GitArguments @('remote', 'get-url', '--push', '--all', 'origin'))
    if ($fetch.Count -ne 1 -or $push.Count -ne 1) {
        throw 'Esta alfa requiere una sola URL efectiva de descarga y de envio.'
    }

    $matchedProfile = $null
    foreach ($key in $profiles.Keys) {
        if ($name -eq $profiles[$key].Name -and $email -eq $profiles[$key].Email) {
            $matchedProfile = $key
            break
        }
    }
    if ($Action -in @('current', 'status')) {
        Write-Host 'CONFIGURACION LOCAL DEL REPOSITORIO' -ForegroundColor Cyan
        Write-Host "Nombre : $name`nEmail  : $email`nFetch  : $($fetch[0])`nPush   : $($push[0])"
        Write-Host "Perfil : $(if ($matchedProfile) { $matchedProfile } else { 'sin coincidencia' })"
        if ($Action -eq 'current') { return }
    }

    if ($Action -eq 'use') {
        $p = $profiles[$Profile]
        $expected = $p.GitHub
    }
    else {
        if (-not $matchedProfile) { throw 'La identidad local no coincide con ningun perfil.' }
        $p = $profiles[$matchedProfile]
        $expected = $p.GitHub
    }

    $parsed = @()
    foreach ($url in @($rawFetch + $rawPush + $fetch + $push)) {
        $remote = Read-ProfileRemote -Url $url
        if ($remote.Owner -ne $expected) {
            throw "El propietario '$($remote.Owner)' no corresponde a la cuenta '$expected'. No se cambio el repositorio."
        }
        $parsed += $remote
    }
    foreach ($remote in $parsed) {
        if ($remote.Repo -ne $parsed[0].Repo) {
            throw 'Las URLs de descarga y envio deben apuntar al mismo repositorio.'
        }
    }

    if ($Action -eq 'use') {
        $lockPath = $gitConfigPath + '.lock'
        $ownsLock = $false
        try {
            # El bloqueo evita cambios parciales y respeta a otros procesos de Git.
            $stream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $ownsLock = $true
            try {
                if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($gitConfigPath)) -ne [Convert]::ToBase64String($originalConfig)) {
                    throw 'La configuracion cambio durante la validacion. Vuelve a ejecutar el comando.'
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
        Write-Host "PERFIL CONFIGURADO: $Profile" -ForegroundColor Green
        Write-Host "Nombre : $($p.Name)`nEmail  : $($p.Email)`nGitHub : $expected"
        return
    }

    foreach ($remote in $parsed) {
        if ($remote.Account -ne $expected) {
            throw "El usuario de una URL no coincide con '$expected'. Ejecuta git-profile use $matchedProfile."
        }
    }
    $effectiveName = Invoke-ProfileGit -GitArguments @('config', '--get', 'user.name') -AllowMissing
    $effectiveEmail = Invoke-ProfileGit -GitArguments @('config', '--get', 'user.email') -AllowMissing
    if ($effectiveName -ne $p.Name -or $effectiveEmail -ne $p.Email) {
        throw 'Otra configuracion sobrescribe la identidad local. Revisa git config --show-origin.'
    }
    foreach ($role in @('AUTHOR', 'COMMITTER')) {
        $ident = Invoke-ProfileGit -GitArguments @('var', "GIT_$($role)_IDENT")
        if ($ident -notmatch '^(?<Name>.*) <(?<Email>[^<>]+)> \d+ [+-]\d{4}$' -or
            $Matches.Name -ne $p.Name -or $Matches.Email -ne $p.Email) {
            throw "La identidad efectiva de $role difiere del perfil. Revisa author.*, committer.* y las variables de entorno de Git."
        }
    }
    Write-Host "OK  Perfil : $matchedProfile`nOK  GitHub : $expected`nOK  Nombre : $name`nOK  Email  : $email" -ForegroundColor Green
    Write-Host "OK  Fetch  : $($fetch[0])`nOK  Push   : $($push[0])" -ForegroundColor Green
    Write-Host 'Configuracion coherente. La autenticacion y los permisos remotos se comprueban por separado.'
}
