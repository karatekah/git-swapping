# Changelog

## v0.1.0-alpha.3

- Check the remote selected by `git push` with no arguments and report the overriding Git setting when the destination differs from `origin`.
- Use English for command output, diagnostics and configuration examples.
- Add a one-command PowerShell installer that sets up accounts interactively and reuses existing profiles.
- Add interactive commands to create, edit, and remove saved accounts from any directory.
- Rename the project to Git Swapping and introduce the two-profile logo.
- Select a profile by GitHub owner with `use -Auto`, and preview the local identity and URL changes with `-WhatIf`.
- Validate planned fetch and push URLs with Git before replacing the local configuration, including URL rewrites.
- Hide unsupported remote URLs in diagnostics and report the expected profile, effective identities and sources of conflicting settings.
- Preserve quotes and Unicode when applying profiles on Windows PowerShell 5.1, and read manually edited UTF-8 profile files with or without a BOM.

## v0.1.0-alpha.2

- Run Windows PowerShell 5.1 and PowerShell 7 in explicit CI jobs, fixing workflow validation before tests start.
- Start the isolated test runner correctly when no Git environment variables are present.
- Preserve alpha.1 history and update the current version references.

## v0.1.0-alpha.1

- Extract the existing PowerShell function into a versioned script loaded from `$PROFILE`.
- Move real account data into ignored `profiles.psd1` and include an editable example.
- Validate repository context, selected profile, HTTPS URL format, owner and matching fetch/push destinations before writing.
- Update explicit push URLs and preserve unrelated local Git settings.
- Stage changes under an exclusive config lock and replace the config atomically.
- Raise errors for failed Git commands and reject unsupported remotes.
- Verify local and effective author/committer identities, including environment overrides.
- Add isolated regression tests and Windows CI for PowerShell 5.1 and 7.
- Add English, Spanish and Italian overviews with installation, commands and alpha limitations.
