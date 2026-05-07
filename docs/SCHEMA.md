# CSAT Schema v1

All collectors emit JSON conforming to this schema. The aggregator validates `schema_version` on read.

## Top-level

| Field | Type | Notes |
|---|---|---|
| `csat_version` | string | Tool version, e.g. `"1.0"` |
| `schema_version` | int | Currently `1` |
| `collected_at_utc` | string | ISO 8601 UTC timestamp |
| `collector` | object | Metadata about the run |
| `identity` | object | Host identity |
| `hardware` | object | Physical/virtual hardware |
| `storage` | array | One entry per logical disk / mount |
| `network` | array | One entry per active interface |
| `roles_features` | array of string | Server roles, features, detected services |
| `services` | array | OS-level services |
| `scheduled_tasks` | array | Scheduled tasks / cron / systemd timers |
| `local_accounts` | array | Local user accounts |
| `admin_group_members` | array of string | Members of Administrators / wheel / sudo |
| `shares` | array | SMB / NFS exports |
| `patches` | object | Patch state |
| `collection_warnings` | array of string | Non-fatal issues encountered during collection |

## `collector`

| Field | Type | Notes |
|---|---|---|
| `platform` | string | `"windows"` or `"linux"` |
| `script_version` | string | Collector version |
| `run_as` | string | User the collector ran as |
| `elevated` | bool | True if running with admin/root |

## `identity`

| Field | Type | Notes |
|---|---|---|
| `hostname` | string | Short name |
| `fqdn` | string | Fully qualified name if joined |
| `domain_or_workgroup` | string | AD domain or workgroup name |
| `machine_guid` | string | Stable machine identifier |
| `os_name` | string | e.g. `"Windows Server 2019 Standard"` |
| `os_version` | string | e.g. `"10.0.17763"` |
| `os_build` | string | Build number |
| `kernel` | string | Linux only |
| `install_date` | string | ISO 8601 |
| `last_boot_utc` | string | ISO 8601 |
| `uptime_seconds` | int | Seconds since boot |
| `timezone` | string | e.g. `"America/Chicago"` |

## `hardware`

| Field | Type | Notes |
|---|---|---|
| `manufacturer` | string | |
| `model` | string | |
| `serial` | string | |
| `bios_version` | string | |
| `cpu_model` | string | |
| `cpu_sockets` | int | |
| `cpu_cores` | int | Physical cores total |
| `cpu_logical` | int | Logical processors |
| `memory_gb` | float | Total physical memory |
| `is_virtual` | bool | |
| `hypervisor` | string | `"VMware"`, `"Hyper-V"`, `"KVM"`, or empty |

## `storage[]`

| Field | Type | Notes |
|---|---|---|
| `device` | string | e.g. `"\\\\?\\Volume{...}"` or `/dev/sda1` |
| `mount_or_letter` | string | `"C:"` or `/var` |
| `filesystem` | string | NTFS, ext4, xfs, etc. |
| `size_gb` | float | |
| `free_gb` | float | |
| `percent_free` | float | |

## `network[]`

| Field | Type | Notes |
|---|---|---|
| `interface` | string | Adapter name |
| `mac` | string | |
| `ipv4` | array of string | |
| `ipv6` | array of string | |
| `subnet` | array of string | CIDR or mask per IP |
| `gateway` | array of string | |
| `dns_servers` | array of string | |
| `dhcp_enabled` | bool | |
| `link_speed_mbps` | int | 0 if unknown |

## `services[]`

| Field | Type | Notes |
|---|---|---|
| `name` | string | |
| `display_name` | string | |
| `state` | string | `running`, `stopped`, etc. |
| `start_mode` | string | `auto`, `manual`, `disabled` |
| `account` | string | Service account if available |

## `scheduled_tasks[]`

| Field | Type | Notes |
|---|---|---|
| `name` | string | |
| `path` | string | Full task path |
| `state` | string | enabled/disabled |
| `last_run` | string | ISO 8601 or empty |
| `next_run` | string | ISO 8601 or empty |
| `run_as` | string | |
| `action` | string | Command line / script path |

## `local_accounts[]`

| Field | Type | Notes |
|---|---|---|
| `name` | string | |
| `enabled` | bool | |
| `is_admin` | bool | |
| `last_logon` | string | ISO 8601 or empty |
| `password_age_days` | int | -1 if unknown |

## `patches`

| Field | Type | Notes |
|---|---|---|
| `last_update_utc` | string | ISO 8601 |
| `pending_reboot` | bool | |
| `recent_kbs_or_packages` | array of string | Most recent updates |

## Versioning

Breaking changes bump `schema_version`. The aggregator supports reading the current schema version and the previous one; older snapshots produce a warning.
