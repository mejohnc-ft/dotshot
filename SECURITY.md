# Security

## Scope

Shot Pill has Screen Recording access and transfers user-selected files over SSH. Treat both capabilities as sensitive.

## Data handling

- Captures are saved under `~/Shots`.
- Destination configuration is stored under `~/Library/Application Support/Shot Pill`.
- Transfers use `/usr/bin/scp` and the user's existing SSH configuration and keys.
- No SSH password, private key, capture, hostname, or usage event is sent to the project maintainers.
- Shot Pill contains no analytics or automatic update service.

## Destination trust

Users are responsible for verifying SSH host keys and access controls on receiving folders. The onboarding test uses normal OpenSSH behavior and does not disable host-key checking.

## Reporting a vulnerability

Do not include screenshots, recordings, credentials, SSH configuration, private keys, or private hostnames in a public issue. Contact the maintainer privately through the security-reporting method configured on the GitHub repository.
