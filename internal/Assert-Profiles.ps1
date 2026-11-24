param([hashtable]$Profiles)

$accounts = @()
foreach ($key in $Profiles.psbase.Keys) {
    $entry = $Profiles[$key]
    if ($key -notmatch '\A[a-z0-9_-]+\z' -or $entry -isnot [hashtable] -or
        $entry.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.Name) -or
        $entry.Email -isnot [string] -or $entry.Email -notmatch '\A[^\s\p{Cc}<>@]+@[^\s\p{Cc}<>@]+\z' -or
        $entry.GitHub -isnot [string] -or $entry.GitHub -notmatch '\A[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?\z' -or
        $entry.Name -match '[\p{Cc}<>]' -or $accounts -contains $entry.GitHub) {
        throw "Invalid profile '$key' or duplicate GitHub account. Check the profile name, author name, email, and GitHub username."
    }
    $accounts += $entry.GitHub
}
