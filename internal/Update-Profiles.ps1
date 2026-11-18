param([string]$Action, [string]$Label, [string]$Path)

. (Join-Path $PSScriptRoot 'ProfileFiles.ps1')

if ($Label -notmatch '^[a-z0-9_-]+$') {
    throw "Usage: git-profile $Action PROFILE. Use letters, numbers, underscores, or hyphens for the profile name."
}

$originalHash = (Get-FileHash -LiteralPath $Path -ErrorAction Stop).Hash
$profiles = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop
& (Join-Path $PSScriptRoot 'Assert-Profiles.ps1') $profiles
if ($Action -eq 'add' -and $profiles.ContainsKey($Label)) {
    throw "Profile '$Label' already exists. Run git-profile edit $Label to update it."
}
if ($Action -ne 'add' -and -not $profiles.ContainsKey($Label)) {
    throw "Profile '$Label' was not found. Run git-profile list."
}

$original = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($original, [ref]$tokens, [ref]$parseErrors)
$findTable = { param($node) $node -is [Management.Automation.Language.HashtableAst] }
$table = $ast.Find($findTable, $true)
if ($parseErrors.Count -or -not $table) { throw 'Could not read the profiles file.' }

$updated = $original
$endOfTable = $table.Extent.EndOffset - 1
if ($Action -eq 'add') {
    $profiles[$Label] = Read-ProfileFields
    $newLine = [Environment]::NewLine
    $prefix = if ($original[$endOfTable - 1] -eq "`n") { '' } else { $newLine }
    $entry = Format-ProfileEntry $Label $profiles[$Label]
    $updated = $original.Insert($endOfTable, "$prefix$entry$newLine")
}
else {
    $pair = $table.KeyValuePairs | Where-Object { $_.Item1.SafeGetValue() -eq $Label } | Select-Object -First 1
    if (-not $pair) { throw "Could not locate profile '$Label' in the profiles file." }
    if ($Action -eq 'edit') {
        $current = $profiles[$Label]
        $changes = Read-ProfileFields -Current $current
        $fields = $pair.Item2.Find($findTable, $true).KeyValuePairs
        # Work backwards so edits do not shift the offsets of earlier values.
        foreach ($field in ($fields | Sort-Object { $_.Item2.Extent.StartOffset } -Descending)) {
            $key = $field.Item1.SafeGetValue()
            if (-not $changes.ContainsKey($key) -or $changes[$key] -ceq $current[$key]) { continue }
            $value = $field.Item2.Extent
            $updated = $updated.Remove($value.StartOffset, $value.EndOffset - $value.StartOffset)
            $updated = $updated.Insert($value.StartOffset, (Format-ProfileField $changes[$key]))
            $current[$key] = $changes[$key]
        }
    }
    else {
        $answer = Read-Host "Remove profile '$Label' (GitHub: $($profiles[$Label].GitHub))? [y/N]"
        if ($answer.Trim() -notmatch '^y(?:es)?$') {
            Write-Host 'Removal cancelled.'
            return
        }
        $profiles.Remove($Label)
        $endOfEntry = $pair.Item2.Extent.EndOffset
        $next = $table.KeyValuePairs | Where-Object { $_.Item1.Extent.StartOffset -ge $endOfEntry } | Select-Object -First 1
        $endOfSeparator = if ($next) { $next.Item1.Extent.StartOffset } else { $endOfTable }
        # Remove separators that belonged to this entry without removing comments.
        $separators = $tokens | Where-Object {
            $_.Kind -eq 'Semi' -and $_.Extent.StartOffset -ge $endOfEntry -and $_.Extent.StartOffset -lt $endOfSeparator
        }
        foreach ($separator in ($separators | Sort-Object { $_.Extent.StartOffset } -Descending)) {
            $updated = $updated.Remove($separator.Extent.StartOffset, 1)
        }
        $startOfEntry = $pair.Item1.Extent.StartOffset
        $updated = $updated.Remove($startOfEntry, $endOfEntry - $startOfEntry)
    }
}

if ($updated -ceq $original) {
    Write-Host "Profile '$Label' is unchanged."
    return
}
& (Join-Path $PSScriptRoot 'Assert-Profiles.ps1') $profiles
$null = [Management.Automation.Language.Parser]::ParseInput($updated, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Could not apply the change to the profiles file.' }
Write-LocalFile -Path $Path -Content $updated -ExpectedHash $originalHash
$result = @{ add = 'Added'; edit = 'Updated'; remove = 'Removed' }
Write-Host "$($result[$Action]) profile '$Label'." -ForegroundColor Green
