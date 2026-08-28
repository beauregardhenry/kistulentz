# Kistulentz Security

## Reporting a vulnerability

If the repository's **Security** tab offers **Report a vulnerability**, use it to send a private report. Otherwise, open a GitHub issue containing no exploit details, private writing, credentials, or API keys and ask the maintainer to establish a private contact path.

Include the affected Kistulentz version, macOS version, Mac architecture, impact, and the smallest safe reproduction you can provide. Do not attach a real manuscript, reference library, project backup, or Keychain material.

For an ordinary bug that does not expose data or credentials, use GitHub Issues directly.

## Supported versions

Security fixes are made against the latest published release. Before reporting, confirm whether the problem remains in that release.

## Local data and credentials

Kistulentz projects and libraries can contain sensitive writing and research. Backups should receive the same protection as the project. OpenAI and Anthropic keys belong in Kistulentz Settings, where the app stores them in the macOS Keychain; they should never be committed to the repository or included in a diagnostic archive.
