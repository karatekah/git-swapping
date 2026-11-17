# Changelog

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
