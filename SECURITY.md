# Security Policy

## Reporting a vulnerability

CSAT is run by sysadmins with the highest privilege available on a host. We take that responsibility seriously.

If you discover a security issue, **please do not open a public issue**. Instead, report it privately:

- Open a private advisory: <https://github.com/Columbia-Cloudworks-LLC/csat/security/advisories/new>
- Or email: security@columbiacloudworks.com

You can expect:

- Acknowledgement within **3 business days**
- An initial assessment within **7 business days**
- Coordinated disclosure once a fix is available

## Scope

In scope:

- Collectors that capture, log, or transmit credentials, secrets, password hashes, or registry hives
- Code execution paths reachable through crafted input to the aggregator (malicious snapshot JSON)
- Privilege escalation through anything CSAT writes to disk
- Any path where CSAT phones home, sends telemetry, or contacts the network

Out of scope:

- Issues requiring a host already compromised at the level CSAT requires to run (Domain Admin / root)
- Snapshots being readable by users with read access to the directory the admin chose to write them to — that is by design; treat snapshots as inventory documents

## Security model recap

- Collectors require elevated privileges and announce that on launch
- Collectors read metadata only — no credentials, no secrets, no hashes
- Collectors do not perform network I/O. No telemetry, ever.
- Aggregator reads JSON from a local directory. It performs no network I/O.
- All third-party Python dependencies are pinned in `aggregator/requirements.txt` and watched by Dependabot.
