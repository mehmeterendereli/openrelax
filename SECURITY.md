# Security policy

OpenRelax can remove files and install a SYSTEM scheduled task. Treat incorrect
path boundaries, privilege changes and disclosure of diagnostic data as security
issues.

## Reporting

Use **Security → Report a vulnerability** on
[the repository security page](https://github.com/mehmeterendereli/openrelax/security)
if that option is available. GitHub private vulnerability reporting must be
enabled separately; this document does not enable it.

If the option is absent, open an issue asking the maintainer for a private
security contact. Include only a generic description; keep exploit steps,
personal logs and sensitive values private until a contact is agreed.
Do not put credentials or personal paths in a public issue.

Provide the commit/version, Windows build, affected mode, impact and a minimal
reproduction using synthetic data. Never demonstrate deletion against a real
user profile. See [GitHub's reporting guidance](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).

## Support

Security fixes are developed against the current source branch. Historical
versions have no published backport or LTS commitment. No guaranteed response
time, signed binary or independent security certification is claimed.

Review [CONTRIBUTING.md](CONTRIBUTING.md) for the path, settings, privacy and task
permission contracts before proposing a fix.
