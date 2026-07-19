# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability or include live hostnames, addresses,
logs, credentials, personal data, or recovery material in a report. Use GitHub's private vulnerability
reporting for this repository. If that channel is unavailable, open a minimal issue asking the
maintainer to establish a private channel without describing the vulnerability.

## Scope

This repository contains architecture, deployment helpers, and configuration schemas. Vulnerabilities
inside a component should be reported to that component's repository. Cross-component trust-boundary
or deployment issues belong here.

## Deployment assumptions

- `services.json` is example data and cannot be used by `scripts/deploy.sh`.
- Real topology belongs in ignored `services.local.json` or an explicitly selected `REGISTRY_PATH`.
- Secrets belong in a secret manager or ignored environment files, never in either registry.
- Internet or private-network exposure requires authentication at the service boundary; network
  location alone is not an authorization control.
- Backups must be encrypted and restoration must be tested independently.

See [`docs/threat-model.md`](docs/threat-model.md) for the system model.
