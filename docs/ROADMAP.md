# CSAT Roadmap

## v1.0 — Core inventory (current)

- Windows + Linux collectors
- Identical JSON schema across platforms
- Human-readable .txt brief
- Python aggregator → XLSX + CSV
- Snapshot diffing

## v1.1 — Quality of life

- `csat-collect.ps1` signing instructions + signed release artifact
- `--exclude` flags on collectors to skip slow sections
- Aggregator `--history` mode keeping all snapshots per host
- Aggregator HTML report option

## v2.0 — Role-aware deep dive

- Active Directory Domain Services health (if DC)
- DHCP scopes and reservations
- DNS zones and forwarders
- IIS sites, app pools, bindings
- SQL Server instances and databases
- File share NTFS permissions
- Certificate inventory
- Firewall rule export
- WSUS / SCCM client state
- systemd unit deep inspection

## v3.0 — Dependency mapping

- Established TCP connections with owning process
- Listening ports → service mapping
- Scheduled task → script path resolution and content hashing
- Service account inventory across hosts
- Applied GPO set
- Cross-host correlation in aggregator (this server depends on that one)

## Non-goals

- Continuous monitoring (use RMM)
- Configuration management (use Ansible/DSC)
- Vulnerability scanning (use a scanner)
- Phoning home or telemetry, ever
