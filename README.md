<div align="center">

<img src="docs/assets/githubswapping-mark.svg" width="96" height="96" alt="GithubSwapping terminal mark" />

# GithubSwapping

**English** · [Español](docs/es/README.md) · [Italiano](docs/it/README.md)

**Every repository, the right account.**

A small PowerShell CLI to keep personal and university Git identities separate, repository by repository.

[![v0.1.0-alpha.1](https://img.shields.io/badge/release-v0.1.0--alpha.1-256b56?style=flat-square)](docs/releases/v0.1.0-alpha.1.md) [![CI](https://github.com/karatekah/GithubSwapping/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/karatekah/GithubSwapping/actions/workflows/ci.yml) [![Windows](https://img.shields.io/badge/platform-Windows-64748b?style=flat-square)](#requirements) [![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-365b8c?style=flat-square)](#requirements)

[Quick start](#quick-start) · [Commands](#commands) · [Alpha notes](docs/releases/v0.1.0-alpha.1.md) · [Report a bug](https://github.com/karatekah/GithubSwapping/issues)

</div>

---

Assign a profile once, then work in each project with its own local identity. **Experimental alpha:** one GitHub account per repository owner, HTTPS remotes, local configuration and explicit checks.

## What the alpha includes

- **Local identities.** Set `user.name` and `user.email` inside the repository, preserving global Git settings.
- **Owner validation.** The selected GitHub account must own the remote repository. A personal profile cannot be assigned to a university-owned repository.
- **Fetch and push checks.** Inspect both effective URLs and update an explicit push URL when present. Both must point to the same repository.
- **Complete updates.** Validate before writing, respect Git's config lock and replace the local configuration only after every staged write succeeds.
- **Useful failures.** Missing remotes, unsupported URLs, conflicting identities and failed commands raise errors instead of printing success.
- **Private account data.** Keep real profiles in ignored `profiles.psd1`; the repository only ships an example.

## Requirements

- Windows with Windows PowerShell 5.1 or PowerShell 7.
- Git 2.31 or later, available in `PATH`.
- A working GitHub HTTPS authentication setup, such as Git Credential Manager.
- A normal working repository with one `origin` fetch URL and at most one explicit push URL.

The script uses atomic file replacement on the local filesystem. Configuration symlinks are rejected. Bare repositories, SSH, GitHub Enterprise hosts and multiple URLs are outside this alpha's scope.

## Quick start

From a fresh clone:

```powershell
git clone https://github.com/karatekah/GithubSwapping.git
cd GithubSwapping
Copy-Item .\profiles.example.psd1 .\profiles.psd1
notepad .\profiles.psd1
```

Replace the example names, emails and GitHub usernames with your accounts. Profile names such as `personal` and `unsa` are labels; the `GitHub` field must match the repository owner. You can use a GitHub-provided `noreply` email to keep your personal email out of commit metadata.

Load the function in the current session:

```powershell
. .\git-profile.ps1
git-profile list
```

For automatic loading, add this **once** to the `$PROFILE` used by your terminal, replacing the example path with the absolute path to your clone:

```powershell
if (Test-Path -LiteralPath 'C:\path\GithubSwapping\git-profile.ps1') {
    . 'C:\path\GithubSwapping\git-profile.ps1'
}
```

Create the profile file and its parent directory first if they do not exist. Keep other profile content. Windows PowerShell and PowerShell 7 have separate profile locations; configure the shell you use. Restart the terminal or run `. $PROFILE` after editing.

Inside a personal repository:

```powershell
cd C:\path\personal-project
git-profile use personal
git-profile status
git fetch origin
```

Use `git-profile use unsa` inside a repository owned by the university account. Profiles remain local to each repository when moving between folders.

## Commands

| Command | Purpose |
| --- | --- |
| `git-profile` or `git-profile help` | Show usage and version |
| `git-profile list` | List configured profiles, including outside a repository |
| `git-profile current` | Show local identity and effective fetch/push URLs |
| `git-profile use PROFILE` | Validate ownership and apply local identity and URLs |
| `git-profile check` | Verify profile, owner, URLs and effective author/committer identities |
| `git-profile status` | Show current settings and run the same verification |

Errors throw a PowerShell exception; automation can use `try` / `catch`. The function never calls `exit` to close your terminal. `use` confirms that configuration was saved; run `check` to detect additional identity overrides.

## Identity and authentication

Commit identity, a remote's username and the credential used for authentication are separate. `check` validates local configuration without network access. A successful fetch demonstrates read access; it does not establish push permissions or prove which stored credential was used.

GithubSwapping does not change global settings, delete credentials or switch the active account in GitHub CLI (`gh`). Existing commits keep their original metadata. To protect your email, use the `noreply` address provided by GitHub for future commits.

## Architecture and stack

| Component | Implementation |
| --- | --- |
| CLI | One dot-sourced PowerShell function in `git-profile.ps1` |
| Profiles | Local PowerShell data file, loaded with `Import-PowerShellDataFile` |
| Git operations | Installed Git executable with checked return codes |
| Configuration update | Staged config, exclusive lock and atomic replacement |
| Verification | Real disposable Git repositories, without network or stored credentials |
| CI | Windows PowerShell 5.1 and PowerShell 7 on GitHub Actions |

## Development

No package installation is required:

```powershell
powershell -NoProfile -File .\tests\git-profile.Tests.ps1
# With PowerShell 7 installed:
pwsh -NoProfile -File .\tests\git-profile.Tests.ps1
```

Tests isolate Git configuration and identities, exercise both profiles and verify failure paths, locks and unchanged configuration after failed updates. They never use real account data or contact GitHub.

## Documentation and next steps

- [Spanish overview](docs/es/README.md) · [Italian overview](docs/it/README.md)
- [Alpha scope and verification](docs/releases/v0.1.0-alpha.1.md)
- [Changelog](CHANGELOG.md)
- Planned: broader Windows usage feedback, an installation helper and more flexible owner mappings. SSH and other providers need separate authentication design before implementation.

Move or rename the clone only after updating its path in `$PROFILE`. Keep a backup of your local `profiles.psd1` before deleting the clone; Git does not track that file.

---

[Made by Karatekah](https://github.com/karatekah)
