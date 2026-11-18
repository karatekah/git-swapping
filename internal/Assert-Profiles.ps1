param([hashtable]$Profiles)

$accounts = @()
foreach ($key in $Profiles.psbase.Keys) {
    $entry = $Profiles[$key]
    if ($key -notmatch '^[a-z0-9_-]+$' -or $entry -isnot [hashtable] -or
        $entry.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.Name) -or
        $entry.Email -isnot [string] -or $entry.Email -notmatch '^[^\s<>@]+@[^\s<>@]+$' -or
        $entry.GitHub -isnot [string] -or $entry.GitHub -notmatch '^[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?$' -or
        $entry.Name -match '[\r\n<>]' -or $accounts -contains $entry.GitHub) {
        throw "Invalid profile '$key' or duplicate GitHub account. Check the profile name, author name, email, and GitHub username."
    }
    $accounts += $entry.GitHub
}
