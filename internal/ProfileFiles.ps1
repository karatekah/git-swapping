function Read-ProfileFields {
    param([hashtable]$Current)

    $prompts = [ordered]@{
        Name   = 'Commit author name'
        Email  = 'Commit email (a GitHub noreply address is accepted)'
        GitHub = 'GitHub username'
    }
    $entry = @{}
    foreach ($field in $prompts.Keys) {
        $prompt = $prompts[$field]
        if ($Current) { $prompt += " [$($Current[$field])]" }
        $value = (Read-Host $prompt).Trim()
        $entry[$field] = if ($Current -and $value -eq '') { $Current[$field] } else { $value }
    }
    $entry
}

function Format-ProfileField {
    param([string]$Value)

    $quoted = [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value)
    "'$quoted'"
}

function Format-ProfileEntry {
    param([string]$Label, [hashtable]$Entry)

    $lines = @("    '$Label' = @{")
    foreach ($field in @('Name', 'Email', 'GitHub')) {
        $lines += "        $field = $(Format-ProfileField $Entry[$field])"
    }
    $lines += '    }'
    $lines -join [Environment]::NewLine
}

function Write-LocalFile {
    param([string]$Path, [string]$Content, [string]$BackupPath, [string]$ExpectedHash)

    $lockPath = "$Path.lock.bak"
    $pendingPath = "$Path.$([guid]::NewGuid().ToString('N')).bak"
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        if ($ExpectedHash -and (-not [IO.File]::Exists($Path) -or
            (Get-FileHash -LiteralPath $Path -ErrorAction Stop).Hash -ne $ExpectedHash)) {
            throw 'The profiles file changed while you were entering data. Run the command again.'
        }
        [IO.File]::WriteAllText($pendingPath, $Content, [Text.UTF8Encoding]::new($true))
        if ($BackupPath) {
            [IO.File]::Replace($pendingPath, $Path, $BackupPath)
        }
        elseif ($ExpectedHash) {
            [IO.File]::Replace($pendingPath, $Path, [NullString]::Value)
        }
        else {
            [IO.File]::Move($pendingPath, $Path)
        }
    }
    finally {
        $lock.Dispose()
        [IO.File]::Delete($lockPath)
        [IO.File]::Delete($pendingPath)
    }
}
