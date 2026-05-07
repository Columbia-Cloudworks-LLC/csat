#!/usr/bin/env python3
"""Generate synthetic CSAT snapshots for aggregator testing."""
import json
from pathlib import Path
from datetime import datetime, timezone, timedelta

OUT = Path(__file__).parent / "snapshots"
OUT.mkdir(exist_ok=True)

NOW = datetime.now(timezone.utc).replace(microsecond=0)


def iso(dt): return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def base(hostname, platform, schema=1):
    return {
        "csat_version": "1.0",
        "schema_version": schema,
        "collected_at_utc": iso(NOW),
        "collector": {
            "platform": platform,
            "script_version": "1.0",
            "run_as": "ADMIN\\nick" if platform == "windows" else "root",
            "elevated": True,
        },
        "collection_warnings": [],
    }


# Windows DC
dc = base("DC01", "windows")
dc.update({
    "identity": {
        "hostname": "DC01",
        "fqdn": "dc01.acme.local",
        "domain_or_workgroup": "acme.local",
        "machine_guid": "11111111-2222-3333-4444-555555555555",
        "os_name": "Windows Server 2019 Standard",
        "os_version": "10.0.17763",
        "os_build": "17763",
        "kernel": "",
        "install_date": iso(NOW - timedelta(days=1200)),
        "last_boot_utc": iso(NOW - timedelta(days=14)),
        "uptime_seconds": 14 * 86400,
        "timezone": "Central Standard Time",
    },
    "hardware": {
        "manufacturer": "Dell Inc.", "model": "PowerEdge R740", "serial": "ABC1234",
        "bios_version": "2.18.1", "cpu_model": "Intel(R) Xeon(R) Silver 4214",
        "cpu_sockets": 2, "cpu_cores": 24, "cpu_logical": 48,
        "memory_gb": 128.0, "is_virtual": False, "hypervisor": "",
    },
    "storage": [
        {"device": "C:", "mount_or_letter": "C:", "filesystem": "NTFS", "size_gb": 200.0, "free_gb": 87.4, "percent_free": 43.7},
        {"device": "D:", "mount_or_letter": "D:", "filesystem": "NTFS", "size_gb": 1000.0, "free_gb": 612.1, "percent_free": 61.2},
    ],
    "network": [{
        "interface": "Intel(R) Ethernet I350", "mac": "AA:BB:CC:00:00:01",
        "ipv4": ["10.10.1.10"], "ipv6": [], "subnet": ["255.255.255.0"],
        "gateway": ["10.10.1.1"], "dns_servers": ["10.10.1.10", "8.8.8.8"],
        "dhcp_enabled": False, "link_speed_mbps": 1000,
    }],
    "roles_features": [
        "AD-Domain-Services", "DNS", "DHCP", "FileAndStorage-Services",
        "GPMC", "RSAT-AD-Tools", "Telnet-Client",
    ],
    "services": [
        {"name": "NTDS", "display_name": "Active Directory Domain Services", "state": "running", "start_mode": "auto", "account": "LocalSystem"},
        {"name": "DNS", "display_name": "DNS Server", "state": "running", "start_mode": "auto", "account": "LocalSystem"},
        {"name": "DHCPServer", "display_name": "DHCP Server", "state": "running", "start_mode": "auto", "account": "NT AUTHORITY\\NetworkService"},
        {"name": "Spooler", "display_name": "Print Spooler", "state": "stopped", "start_mode": "disabled", "account": "LocalSystem"},
        {"name": "W32Time", "display_name": "Windows Time", "state": "running", "start_mode": "auto", "account": "NT AUTHORITY\\LocalService"},
    ],
    "scheduled_tasks": [
        {"name": "AD-Backup", "path": "\\Acme\\", "state": "ready", "last_run": iso(NOW - timedelta(days=1)),
         "next_run": iso(NOW + timedelta(days=1)), "run_as": "ACME\\svc-backup", "action": "C:\\Scripts\\backup-ad.ps1"},
    ],
    "local_accounts": [
        {"name": "Administrator", "enabled": True, "is_admin": True, "last_logon": iso(NOW - timedelta(days=2)), "password_age_days": 87},
        {"name": "Guest", "enabled": False, "is_admin": False, "last_logon": "", "password_age_days": -1},
    ],
    "admin_group_members": ["ACME\\Domain Admins", "Administrator", "ACME\\nick"],
    "shares": [
        {"name": "NETLOGON", "path": "C:\\Windows\\SYSVOL\\sysvol\\acme.local\\SCRIPTS", "description": "Logon server share"},
        {"name": "SYSVOL", "path": "C:\\Windows\\SYSVOL\\sysvol", "description": "Logon server share"},
    ],
    "patches": {
        "last_update_utc": iso(NOW - timedelta(days=18)),
        "pending_reboot": False,
        "recent_kbs_or_packages": ["KB5034441 (2026-04-15)", "KB5034440 (2026-04-15)"],
    },
})


# Windows file server
fs = base("FS01", "windows")
fs.update({
    "identity": {
        "hostname": "FS01", "fqdn": "fs01.acme.local", "domain_or_workgroup": "acme.local",
        "machine_guid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "os_name": "Windows Server 2022 Standard", "os_version": "10.0.20348", "os_build": "20348",
        "kernel": "", "install_date": iso(NOW - timedelta(days=400)),
        "last_boot_utc": iso(NOW - timedelta(days=3)), "uptime_seconds": 3 * 86400,
        "timezone": "Central Standard Time",
    },
    "hardware": {
        "manufacturer": "VMware, Inc.", "model": "VMware Virtual Platform", "serial": "VMware-42-..",
        "bios_version": "VMW71.00V.20.10", "cpu_model": "Intel(R) Xeon(R) Gold 6248",
        "cpu_sockets": 4, "cpu_cores": 4, "cpu_logical": 4,
        "memory_gb": 32.0, "is_virtual": True, "hypervisor": "VMware",
    },
    "storage": [
        {"device": "C:", "mount_or_letter": "C:", "filesystem": "NTFS", "size_gb": 100.0, "free_gb": 41.2, "percent_free": 41.2},
        {"device": "E:", "mount_or_letter": "E:", "filesystem": "NTFS", "size_gb": 4096.0, "free_gb": 312.5, "percent_free": 7.6},
    ],
    "network": [{
        "interface": "vmxnet3 Ethernet", "mac": "00:50:56:AA:BB:01",
        "ipv4": ["10.10.1.20"], "ipv6": [], "subnet": ["255.255.255.0"],
        "gateway": ["10.10.1.1"], "dns_servers": ["10.10.1.10"],
        "dhcp_enabled": False, "link_speed_mbps": 10000,
    }],
    "roles_features": ["FileAndStorage-Services", "FS-FileServer", "FS-SMB1", "Storage-Replica"],
    "services": [
        {"name": "LanmanServer", "display_name": "Server", "state": "running", "start_mode": "auto", "account": "LocalSystem"},
        {"name": "MSiSCSI", "display_name": "Microsoft iSCSI Initiator Service", "state": "running", "start_mode": "auto", "account": "LocalSystem"},
    ],
    "scheduled_tasks": [],
    "local_accounts": [
        {"name": "Administrator", "enabled": True, "is_admin": True, "last_logon": iso(NOW - timedelta(days=10)), "password_age_days": 412},
    ],
    "admin_group_members": ["ACME\\Domain Admins", "Administrator"],
    "shares": [
        {"name": "Shared", "path": "E:\\Shared", "description": "Department shared folder"},
        {"name": "Profiles", "path": "E:\\Profiles", "description": "Roaming user profiles"},
        {"name": "Backups", "path": "E:\\Backups", "description": ""},
    ],
    "patches": {
        "last_update_utc": iso(NOW - timedelta(days=5)),
        "pending_reboot": True,
        "recent_kbs_or_packages": ["KB5034441 (2026-05-02)"],
    },
    "collection_warnings": ["E: is below 10% free space."],
})


# Linux web server
web = base("web01", "linux")
web.update({
    "identity": {
        "hostname": "web01", "fqdn": "web01.acme.local", "domain_or_workgroup": "acme.local",
        "machine_guid": "abcdef1234567890abcdef1234567890",
        "os_name": "Ubuntu 22.04.4 LTS", "os_version": "22.04", "os_build": "jammy",
        "kernel": "5.15.0-101-generic", "install_date": iso(NOW - timedelta(days=210)),
        "last_boot_utc": iso(NOW - timedelta(days=42)), "uptime_seconds": 42 * 86400,
        "timezone": "America/Chicago",
    },
    "hardware": {
        "manufacturer": "QEMU", "model": "Standard PC", "serial": "",
        "bios_version": "1.16.0", "cpu_model": "AMD EPYC 7763 64-Core",
        "cpu_sockets": 1, "cpu_cores": 4, "cpu_logical": 4,
        "memory_gb": 8.0, "is_virtual": True, "hypervisor": "KVM",
    },
    "storage": [
        {"device": "/dev/vda1", "mount_or_letter": "/", "filesystem": "ext4", "size_gb": 50.0, "free_gb": 31.2, "percent_free": 62.4},
        {"device": "/dev/vdb1", "mount_or_letter": "/var/www", "filesystem": "ext4", "size_gb": 200.0, "free_gb": 138.7, "percent_free": 69.3},
    ],
    "network": [{
        "interface": "ens3", "mac": "52:54:00:aa:bb:01",
        "ipv4": ["10.10.2.50"], "ipv6": ["fe80::5054:ff:feaa:bb01"], "subnet": ["10.10.2.50/24"],
        "gateway": ["10.10.2.1"], "dns_servers": ["10.10.1.10", "1.1.1.1"],
        "dhcp_enabled": True, "link_speed_mbps": 1000,
    }],
    "roles_features": ["role:http", "role:https", "role:ssh", "svc:nginx", "svc:sshd"],
    "services": [
        {"name": "nginx", "display_name": "A high performance web server", "state": "active", "start_mode": "enabled", "account": "www-data"},
        {"name": "ssh", "display_name": "OpenBSD Secure Shell server", "state": "active", "start_mode": "enabled", "account": "root"},
        {"name": "ufw", "display_name": "Uncomplicated firewall", "state": "active", "start_mode": "enabled", "account": "root"},
    ],
    "scheduled_tasks": [
        {"name": "logrotate.timer", "path": "/systemd/timers", "state": "enabled",
         "last_run": iso(NOW - timedelta(hours=14)), "next_run": iso(NOW + timedelta(hours=10)),
         "run_as": "root", "action": "logrotate.timer"},
        {"name": "crontab:1", "path": "/etc/crontab", "state": "enabled",
         "last_run": "", "next_run": "",
         "run_as": "root", "action": "0 3 * * * /usr/local/bin/cert-renew.sh"},
    ],
    "local_accounts": [
        {"name": "root", "enabled": True, "is_admin": True, "last_logon": iso(NOW - timedelta(days=1)), "password_age_days": 200},
        {"name": "deploy", "enabled": True, "is_admin": True, "last_logon": iso(NOW - timedelta(hours=4)), "password_age_days": 85},
    ],
    "admin_group_members": ["root", "deploy"],
    "shares": [],
    "patches": {
        "last_update_utc": iso(NOW - timedelta(days=4)),
        "pending_reboot": False,
        "recent_kbs_or_packages": ["nginx-core", "openssl", "libssl3"],
    },
})


# Linux DB server
db = base("db01", "linux")
db.update({
    "identity": {
        "hostname": "db01", "fqdn": "db01.acme.local", "domain_or_workgroup": "acme.local",
        "machine_guid": "fedcba0987654321fedcba0987654321",
        "os_name": "Red Hat Enterprise Linux 9.3", "os_version": "9.3", "os_build": "Plow",
        "kernel": "5.14.0-362.13.1.el9_3.x86_64", "install_date": iso(NOW - timedelta(days=120)),
        "last_boot_utc": iso(NOW - timedelta(days=7)), "uptime_seconds": 7 * 86400,
        "timezone": "America/Chicago",
    },
    "hardware": {
        "manufacturer": "Dell Inc.", "model": "PowerEdge R650", "serial": "DBSRV01",
        "bios_version": "1.13.4", "cpu_model": "Intel(R) Xeon(R) Gold 6354",
        "cpu_sockets": 2, "cpu_cores": 36, "cpu_logical": 72,
        "memory_gb": 384.0, "is_virtual": False, "hypervisor": "",
    },
    "storage": [
        {"device": "/dev/sda1", "mount_or_letter": "/", "filesystem": "xfs", "size_gb": 100.0, "free_gb": 64.5, "percent_free": 64.5},
        {"device": "/dev/sdb1", "mount_or_letter": "/var/lib/postgresql", "filesystem": "xfs", "size_gb": 2048.0, "free_gb": 956.3, "percent_free": 46.7},
    ],
    "network": [{
        "interface": "eno1", "mac": "00:1c:c4:aa:bb:02",
        "ipv4": ["10.10.2.60"], "ipv6": [], "subnet": ["10.10.2.60/24"],
        "gateway": ["10.10.2.1"], "dns_servers": ["10.10.1.10"],
        "dhcp_enabled": False, "link_speed_mbps": 10000,
    }],
    "roles_features": ["role:postgres", "role:ssh", "svc:postgresql", "svc:sshd"],
    "services": [
        {"name": "postgresql", "display_name": "PostgreSQL database server", "state": "active", "start_mode": "enabled", "account": "postgres"},
        {"name": "sshd", "display_name": "OpenSSH server daemon", "state": "active", "start_mode": "enabled", "account": "root"},
        {"name": "firewalld", "display_name": "firewalld - dynamic firewall daemon", "state": "active", "start_mode": "enabled", "account": "root"},
    ],
    "scheduled_tasks": [
        {"name": "pg_dump.timer", "path": "/systemd/timers", "state": "enabled",
         "last_run": iso(NOW - timedelta(hours=8)), "next_run": iso(NOW + timedelta(hours=16)),
         "run_as": "postgres", "action": "pg_dump.timer"},
    ],
    "local_accounts": [
        {"name": "root", "enabled": True, "is_admin": True, "last_logon": iso(NOW - timedelta(days=3)), "password_age_days": 119},
        {"name": "postgres", "enabled": True, "is_admin": False, "last_logon": iso(NOW - timedelta(hours=8)), "password_age_days": 119},
        {"name": "dba", "enabled": True, "is_admin": True, "last_logon": iso(NOW - timedelta(days=1)), "password_age_days": 32},
    ],
    "admin_group_members": ["root", "dba"],
    "shares": [],
    "patches": {
        "last_update_utc": iso(NOW - timedelta(days=2)),
        "pending_reboot": False,
        "recent_kbs_or_packages": ["postgresql-server-15.5", "kernel-5.14.0-362.18"],
    },
})


# Same FS01 host, but newer snapshot - simulates what diff looks like
fs_new = json.loads(json.dumps(fs))  # deep copy
fs_new["collected_at_utc"] = iso(NOW + timedelta(hours=12))
fs_new["identity"]["last_boot_utc"] = iso(NOW + timedelta(hours=10))
fs_new["identity"]["uptime_seconds"] = 7200
fs_new["storage"][1]["free_gb"] = 285.4  # disk shrank
fs_new["storage"][1]["percent_free"] = 6.97
fs_new["patches"]["pending_reboot"] = False
fs_new["patches"]["last_update_utc"] = iso(NOW + timedelta(hours=10))
fs_new["admin_group_members"] = ["ACME\\Domain Admins", "Administrator", "ACME\\contractor-jdoe"]  # new admin appeared
fs_new["services"].append({"name": "WSearch", "display_name": "Windows Search", "state": "running", "start_mode": "auto", "account": "LocalSystem"})


def write(name_stamp, data):
    p = OUT / name_stamp
    p.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(p)


write("DC01_2026-05-07T1200Z.json", dc)
write("FS01_2026-05-07T1200Z.json", fs)
write("FS01_2026-05-08T0000Z.json", fs_new)
write("web01_2026-05-07T1200Z.json", web)
write("db01_2026-05-07T1200Z.json", db)

print("\nGenerated 5 sample snapshots in", OUT)
