# CSAT — Computer Situational Awareness Tool

[![CI](https://github.com/Columbia-Cloudworks-LLC/csat/actions/workflows/ci.yml/badge.svg)](https://github.com/Columbia-Cloudworks-LLC/csat/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Columbia-Cloudworks-LLC/csat?display_name=tag&sort=semver)](https://github.com/Columbia-Cloudworks-LLC/csat/releases)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](#)
[![Bash](https://img.shields.io/badge/Bash-4%2B-4EAA25?logo=gnubash&logoColor=white)](#)
[![Python](https://img.shields.io/badge/Python-3.8%2B-3776AB?logo=python&logoColor=white)](#)

**Get any admin up to speed in any environment, fast.**

CSAT is a portable, agentless inventory toolkit for MSPs and sysadmins who inherit poorly documented servers. Run a single script on a host with the highest privilege you have, get a normalized JSON snapshot plus a human-readable brief. Feed any number of snapshots to the aggregator and get a single source-of-truth spreadsheet — your support matrix.

Owned by Columbia Cloudworks LLC. MIT licensed.

## Why

You walk into a new customer environment. You have admin creds. You have a list of hostnames and IPs. You have no idea what any of these boxes actually do. CSAT answers "what is this server" in under 60 seconds, and produces an artifact you can share with the rest of your team.

## What it is not

CSAT is not RMM. It is not a CMDB. It does not phone home, install agents, or require internet access. It collects metadata only — never credentials, secrets, or password hashes.

## Components

| Component | Path | Purpose |
|---|---|---|
| Windows collector | `collectors/csat-collect.ps1` | Run on Windows Server 2012 R2+ / Win10+. PowerShell 5.1 compatible, no external modules. |
| Linux collector | `collectors/csat-collect.sh` | Run on RHEL/Debian/Ubuntu/SUSE families. POSIX bash, graceful tool fallbacks. |
| Aggregator | `aggregator/csat` | Python 3.8+ CLI. Reads snapshot directory, emits XLSX + CSV. |

All three are single-file deliverables. No installers.

## Quick start

### 1. Collect on a Windows host

```powershell
# Open PowerShell as Administrator
.\csat-collect.ps1 -OutputPath C:\Temp -Yes
```

Produces:

- `C:\Temp\HOSTNAME_2026-05-07T1240Z.json`
- `C:\Temp\HOSTNAME_2026-05-07T1240Z.txt`

### 2. Collect on a Linux host

```bash
sudo ./csat-collect.sh -o /tmp -y
```

Same output naming convention.

### 3. Build the support matrix

```bash
# On your workstation
pip install openpyxl
python aggregator/csat build ./snapshots/ -o matrix.xlsx
```

Drop every JSON you've collected into one folder, point the aggregator at it.

### 4. Diff snapshots over time

```bash
python aggregator/csat diff old.json new.json
```

Shows what changed — new admins, new services, disk drift, role changes, patch level.

## Output schema

Both collectors emit identical JSON conforming to `csat-schema v1`. See [`docs/SCHEMA.md`](docs/SCHEMA.md).

## Security model

- Collectors require elevated privileges and say so on launch.
- No credentials, secrets, password hashes, or registry hives are exported.
- Output files contain infrastructure metadata that is sensitive in aggregate. Treat them like inventory documents — not public, but not state secrets either.
- All collection is wrapped in error handlers. A failed query becomes a warning, not a crash. Inspect `collection_warnings` in every snapshot.

## Status

v1.0 — core inventory only. Roadmap in [`docs/ROADMAP.md`](docs/ROADMAP.md).

## License

MIT. See [`LICENSE`](LICENSE).
