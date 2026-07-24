# Proxmox host exporters (node_exporter + smartctl_exporter)

Physical disk SMART data is only visible on the **bare-metal Proxmox hosts**
(Melchior, Balthasar, Casper). The Talos and TrueNAS VMs only receive
qemu-passthrough block devices, which expose no SMART — including the 3×10TB HDDs
backing the TrueNAS RAIDZ1 media pool, whose only SMART vantage point is the
Proxmox host. These two exporters run as systemd services on each hypervisor and
are pull-scraped by the in-cluster Prometheus.

The Kubernetes side is GitOps-managed and already in this repo:

- [`proxmox-scrapeconfig.yaml`](proxmox-scrapeconfig.yaml) — Prometheus scrape targets
- [`proxmox-alert-rules.yaml`](proxmox-alert-rules.yaml) — SMART, OOM, reboot and ECC alerts (→ Telegram)
- `scrapeConfigSelectorNilUsesHelmValues: false` in `prometheus-stack-values.yaml`

**This file is the manual, host-side half.** Run it once per Proxmox node.

> Update the host IPs in `proxmox-scrapeconfig.yaml` if they differ from the
> assumed VLAN 10 addresses `10.1.10.11/12/13` (Melchior/Balthasar/Casper).

---

## 1. Firewall (once)

The scrape arrives from the Kubernetes subnet (Cilium masquerades pod egress to
the worker node IP), so the source is `10.1.20.0/24`.

- **UniFi:** allow **VLAN 20 (Kubernetes) → VLAN 10 (Management)** on `tcp 9100, 9633`.
- **Proxmox host firewall:** if `pve-firewall` is enabled, add to
  `/etc/pve/firewall/cluster.fw` (applies to all nodes) under `[RULES]`:

  ```
  IN ACCEPT -source 10.1.20.0/24 -p tcp -dport 9100 -log nolog # node_exporter
  IN ACCEPT -source 10.1.20.0/24 -p tcp -dport 9633 -log nolog # smartctl_exporter
  ```

  If the Proxmox firewall is disabled (default on many homelab installs), only
  the UniFi rule is needed.

---

## 2. node_exporter — one command

Packaged in Debian, so on each Proxmox host:

```bash
apt-get update && apt-get install -y prometheus-node-exporter
```

It starts and enables itself on `:9100`. Verify:

```bash
curl -s localhost:9100/metrics | head
```

To check ECC/EDAC exposure on a host:

```bash
curl -s localhost:9100/metrics | grep node_edac
```

### Known gap: ECC errors on Melchior are not monitored

Measured on all three hosts, the result is the inverse of what you'd expect:

| Host | ECC RAM? | `node_edac_*` exposed? |
|------|----------|------------------------|
| **Melchior** (Xeon E-2324G) | **yes**, 128GB DDR4 ECC | **no** — no driver |
| Balthasar / Casper (i5-12600H) | no (DDR5 non-ECC) | yes, via `igen6_edac` (always 0) |

- **Melchior has no upstream EDAC driver.** Xeon E-2300 / Rocket Lake is a hole in
  kernel EDAC support: `ie31200_edac`'s device list stops at 8th/9th gen, and
  `igen6_edac` (client SoC / IBECC) doesn't match it. There is no module to load —
  `modprobe` will just return "No such device", and `rasdaemon` / `ras-mc-ctl`
  report "No memories found at via edac" for the same reason. This is a known,
  widely-reported gap on the Xeon E-2300 family, not a misconfiguration.
- **Balthasar/Casper's counters are cosmetic.** `igen6_edac` attaches, but the RAM
  is non-ECC and IBECC is not enabled in BIOS, so the counters can never leave 0.
  (DDR5's mandatory on-die ECC is internal to the DRAM and invisible to the host.)

**This does not affect ECC itself.** Detection and correction happen in the memory
controller and DIMMs — EDAC is only a reporting interface. On Melchior ECC is fully
active: it silently corrects single-bit flips (the data-integrity protection TrueNAS
depends on) and halts the host on uncorrectable errors rather than writing
corruption to disk. Nothing about the missing driver degrades that.

**What's actually lost is the counter, not the coverage:**

- Uncorrectable errors still raise a Machine Check Exception, which the kernel logs
  and generally panics on — `ProxmoxHostRebooted` catches the aftermath.
- Corrected errors are still handled via CMCI and written to the kernel log
  (`mce: [Hardware Error] ... Corrected error, no action required`) — they are
  absent from Prometheus, not from the machine. Check any host with:

  ```bash
  journalctl -k --no-pager | grep -iE "hardware error|mce:"
  ```

So the precise gap is a **missing trend for corrected errors**: no early warning
that a DIMM is degrading, and no Telegram alert.

**No ECC alert rules ship, deliberately** — a rule that can never fire reads as
coverage while providing none. If Melchior ever gains EDAC driver support (upstream
is refactoring `ie31200` for newer SoCs), `node_edac_correctable_errors_total` and
`node_edac_uncorrectable_errors_total` will appear on their own and are worth
alerting on at that point.

**Optional, untested:** `apt install rasdaemon` on Melchior may close it. rasdaemon
consumes the `mce_record` tracepoint, which is independent of the EDAC driver, so
MCE-sourced memory errors can be recorded even here (`ras-mc-ctl --error-count`
will still be empty — that one reads EDAC sysfs — but `ras-mc-ctl --errors` and
`/var/lib/rasdaemon/ras-mc_event.db` should populate). Could later be exported via
node_exporter's textfile collector.

If closing this gap matters, the practical route is **out-of-band via Melchior's
BMC/IPMI** (already on VLAN 10), which logs ECC events to the SEL independently of
the OS — either watched manually with `ipmitool sel list`, or scraped with
prometheus-community's `ipmi_exporter`. Not set up today.

---

## 3. smartctl_exporter — apt from trixie-backports (PVE 9 / Debian 13)

`smartctl_exporter` is packaged in `trixie-backports` (0.14.0). Proxmox 9 doesn't
enable the backports repo by default, so add it once, then install. On each host:

```bash
echo 'deb http://deb.debian.org/debian trixie-backports main' > /etc/apt/sources.list.d/backports.list
apt update
apt install -t trixie-backports prometheus-smartctl-exporter
```

`smartmontools` (the `smartctl` binary it shells out to) already ships with
Proxmox and is pulled in as a dependency anyway. The package installs and enables
its own systemd service (`prometheus-smartctl-exporter`) on `:9633`.

Confirm it can actually read the disks — this should print one line per physical
disk, each ending in `1` (healthy) or `0` (failing):

```bash
curl -s localhost:9633/metrics | grep smartctl_device_smart_status
```

**If you get zero lines**, the daemon can't reach the raw devices. Check how the
packaged unit runs with `systemctl cat prometheus-smartctl-exporter`, then grant
raw device access via a drop-in (`systemctl edit prometheus-smartctl-exporter`):

```ini
[Service]
User=root
```

`smartctl` needs raw device access; running as root is the simplest grant. Then
`systemctl restart prometheus-smartctl-exporter` and re-check.

---

## 4. Verify the cluster side

Once the firewall + services are up on all three hosts, ArgoCD will have already
synced the manifests. Check Prometheus picked up the targets:

- Prometheus UI → **Status → Targets** → `proxmox-node` and `proxmox-smartctl`
  should show 3 UP targets each (`instance` = melchior/balthasar/casper).
- Query `smartctl_device_smart_status` — one series per disk per host.

Alerts (`ProxmoxSmartHealthFailed`, `ProxmoxSmartPendingSectors`, etc.) route to
Telegram automatically via the existing alertmanager `severity` routing.

---

## Upgrades

Both are apt packages, so `apt upgrade` keeps them current — no manual version
bumps, no Renovate gap. Debian backports is configured with
`ButAutomaticUpgrades: yes`, so once the smartctl exporter is installed it is
auto-upgraded to newer backports versions just like any other package (unlike
new installs, which still need the explicit `-t trixie-backports`).
