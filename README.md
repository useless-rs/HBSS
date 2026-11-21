# HBSS — Hardware Benchmark Suite Script

**HBSS** is a lightweight, privacy-conscious hardware detection and benchmarking suite for Linux, macOS, and Windows. It runs from a single command, needs no installation, no administrator/root privileges, and no configuration. Version **1.0.0**. Licensed **GPL-3.0-or-later**.

HBSS gives you a fast, honest picture of the hardware in front of you: what is installed, what each component can do, and — where a trustworthy engine is available — how it performs. It is deliberately conservative about what it downloads, what it executes, and what it records.

> [!WARNING]
> ## Remote execution disclaimer
> `curl | sh` and `irm | iex` **execute code retrieved from a remote server on your machine**. HTTPS protects the transport, but it does **not** establish that the repository is trustworthy or that its contents have not changed. Only run these commands from a source you trust. If verification is required, download and review `run` / `run.ps1` (and the files they fetch) before executing them. HBSS itself never asks you to disable security features.

---

## Contents

1. [What it does](#what-it-does)
2. [One-line entry points](#one-line-entry-points)
3. [Profiles: Quick, Standard, Full](#profiles-quick-standard-full)
4. [Command-line options](#command-line-options)
5. [Hardware detection capabilities](#hardware-detection-capabilities)
6. [Benchmark categories](#benchmark-categories)
7. [Established engines used](#established-engines-used)
8. [OS-specific benchmarks](#os-specific-benchmarks)
9. [What each benchmark measures](#what-each-benchmark-measures)
10. [What each benchmark does NOT measure](#what-each-benchmark-does-not-measure)
11. [Downloads and temporary execution behavior](#downloads-and-temporary-execution-behavior)
12. [Security model](#security-model)
13. [Trace and privacy](#trace-and-privacy)
14. [Safety restrictions](#safety-restrictions)
15. [Benchmark methodology](#benchmark-methodology)
16. [Known limitations](#known-limitations)
17. [Example output](#example-output)
18. [Ethics](#ethics)
19. [Disclaimer](#disclaimer)
20. [License](#license)

---

## What it does

HBSS performs three jobs, in one pass:

- **Inventory.** It reports CPU, GPU, memory, storage, network, accelerator (NPU), thermal, and "other" hardware using built-in operating-system interfaces (`/proc` and `/sys`, WMI/CIM, `system_profiler`). Detection is read-only and unprivileged.
- **Measurement.** It runs short, bounded benchmarks — either lightweight self-contained HBSS implementations or recognized open-source engines — using a temporary working directory and a temporary test file only.
- **Reporting.** It prints a structured report with consistent sections, explicit units, engine attribution, and a clear list of what was skipped and why. A machine-readable form mirrors the same data.

Design priorities, in order: **do no harm**, **do not phone home**, **be honest about provenance**, **be useful immediately**. By default HBSS downloads nothing from third parties and uses only what the OS and the machine already provide.

---

## One-line entry points

### POSIX (Linux, macOS, BSD — `sh`)

```sh
curl -fsSL https://raw.githubusercontent.com/useless-rs/HBSS/main/run | sh
```

Quick profile:

```sh
curl -fsSL https://raw.githubusercontent.com/useless-rs/HBSS/main/run | sh -s -- --quick
```

### Windows 10+ (PowerShell 5.1 or later)

```powershell
irm https://raw.githubusercontent.com/useless-rs/HBSS/main/run.ps1 | iex
```

Quick profile:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/useless-rs/HBSS/main/run.ps1'))) -Quick
```

See the [remote execution disclaimer](#remote-execution-disclaimer) at the top of this document before using any of these commands.

---

## Profiles: Quick, Standard, Full

A profile sets the overall time budget, which categories run, per-test timeouts, and storage test-file sizes. You can always narrow further with `--only` / `--skip`.

| Profile | Wall-clock budget | What it includes | downloads / long work |
|---|---|---|---|
| **Quick** | ≤ 90 seconds | Full hardware detection, short CPU single- and multi-core, short memory bandwidth, short storage, GPU detection plus a quick GPU benchmark if an engine is available, basic telemetry snapshot | No third-party downloads; no long rendering, AI, or large-storage tests; STREAM is **not** compiled |
| **Standard** | ~5–10 minute cap | All safe categories at moderate workloads: CPU scaling, memory bandwidth, representative storage patterns, optional opted-in engines, loopback skipped | Third-party engines only with explicit opt-in; moderate storage files |
| **Full** | ~10–15 minute cap | More scaling points, memory latency, additional storage access patterns, loopback network test, additional accelerators where inventory exposes them | Same opt-in rules; larger allowed storage files and per-test timeouts |

**Hard per-test timeouts** (profile order Quick / Standard / Full):

| Category | Quick | Standard | Full |
|---|---|---|---|
| CPU | 20 s | 60 s | 120 s |
| Memory | 10 s | 30 s | 60 s |
| Storage | 15 s | 45 s | 90 s |
| GPU | 30 s | 120 s | 240 s |

**Storage test-file caps** (profile order Quick / Standard / Full): **256 MiB / 1 GiB / 2 GiB**. A test that cannot finish inside its cap is stopped and labeled as time-limited; it is never allowed to grow without bound.

Long-running tests are skipped on battery power. There are no unlimited loops.

---

## Command-line options

### POSIX flags (`run`)

| Flag | Effect |
|---|---|
| `--quick` | Use the Quick profile (≤ 90 s). |
| `--standard` | Use the Standard profile (5–10 min cap). Default when no profile is given. |
| `--full` | Use the Full profile (10–15 min cap). |
| `--only <csv>` | Run only the listed categories. |
| `--skip <csv>` | Skip the listed categories (applied after `--only`). |
| `--all-drives` | Opt in to testing all eligible fixed local volumes (see Storage below). Off by default. |
| `--no-downloads` | Force **no** downloads, even if other flags permit them. |
| `--download-benchmarks` | Opt in to pinned official engine downloads with SHA-256 verification. |
| `--use-installed-benchmarks` | Permit execution of installed proprietary tools whose license allows it (never automatic). |
| `--no-proprietary` | Disable all proprietary-tool integration, including detection of Geekbench/Cinebench. |
| `--allow-network` | Permit network activity; required (together with `--endpoint`) for external tests. |
| `--allow-large-downloads` | Additionally permit large assets such as Blender. |
| `--endpoint <host>` | Explicit peer host for an external network test. |
| `--help` | Print usage and exit. |
| `--version` | Print version (`HBSS 1.0.0`) and exit. |

### PowerShell parameters (`run.ps1`)

| Parameter | Effect |
|---|---|
| `-Quick` | Use the Quick profile (≤ 90 s). |
| `-Standard` | Use the Standard profile (default). |
| `-Full` | Use the Full profile. |
| `-Only` | Run only the listed categories. |
| `-Skip` | Skip the listed categories. |
| `-AllDrives` | Opt in to testing all eligible fixed local volumes. |
| `-NoDownloads` | Force no downloads regardless of other switches. |
| `-DownloadBenchmarks` | Opt in to pinned official engine downloads with SHA-256 verification. |
| `-UseInstalledBenchmarks` | Permit execution of installed, license-permitting proprietary tools. |
| `-NoProprietary` | Disable all proprietary-tool integration. |
| `-AllowNetwork` | Permit network activity. |
| `-AllowLargeDownloads` | Permit large assets such as Blender. |
| `-Endpoint` | Explicit peer host for an external network test. |
| `-Help` | Print usage and exit. |
| `-Version` | Print version and exit. |

### Category names for `--only` / `--skip`

`cpu`, `gpu`, `memory`, `storage`, `network`, `npu`, `crypto`, `thermals`, `other`

Example:

```sh
curl -fsSL https://raw.githubusercontent.com/useless-rs/HBSS/main/run |
  sh -s -- --standard --only cpu,memory --skip thermals --no-downloads
```

---

## Hardware detection capabilities

HBSS reads hardware facts from interfaces the operating system already exposes — no download, no admin:

- **CPU:** model, vendor, family/model/stepping, logical CPUs, physical cores, sockets, threads per core, cache sizes, frequency where exposed, topology and NUMA layout (`/proc/cpuinfo`, `/sys/devices/system/cpu`, `lscpu`; `Win32_Processor`; `system_profiler SPHardwareDataType`, `sysctl`).
- **GPU:** device name, vendor, VRAM where reported, driver version, and available compute APIs (PCI sysfs / `lspci`; `Win32_VideoController`; `system_profiler SPDisplaysDataType`).
- **Memory:** total installed RAM, module counts/sizes/speeds where exposed, and swap summary (`/proc/meminfo`; `Win32_PhysicalMemory` / `Win32_PhysicalMemoryArray`; `SPMemoryDataType`).
- **Storage:** model, capacity, bus/interface, and the backing filesystem of the temp working directory (`lsblk`, `/sys/block`; `Get-PhysicalDisk`, `Win32_DiskDrive`; `SPNVMeDataType`).
- **Network:** interface names, link speed, and addresses (OS networking APIs; no traffic generated unless explicitly permitted).
- **NPU / accelerators:** presence and name from inventory only (vendor runtime/device enumeration where present).
- **Thermals / power:** available temperature sensors, fan readings, and power source (AC/battery) from unprivileged interfaces only.
- **Other / platform:** OS name and version, kernel, architecture, host name, firmware/BIOS summary where readable without root.

Optional detection tools (`smartctl`, `sensors`, `hwinfo`, `dmidecode`, `lspci`) are used only if already installed and only for the data an unprivileged caller can read. HBSS never installs them and never elevates to read restricted data.

---

## Benchmark categories

| Code | Category | Representative measurements |
|---|---|---|
| `cpu` | CPU | Integer/float throughput, single-core, multi-core, scaling efficiency |
| `gpu` | GPU | Rendering/compute throughput where an engine is available; otherwise detection only |
| `memory` | Memory | Bandwidth and (in Full) pointer-chasing latency |
| `storage` | Storage | Sequential throughput and random IOPS on a temporary file |
| `network` | Network | Loopback throughput (Full) or an explicit external endpoint (strict opt-in) |
| `npu` | AI / NPU | Inventory only; no standardized portable performance number |
| `crypto` | Crypto | Symmetric cipher and hash throughput via installed OpenSSL `speed` |
| `thermals` | Thermals | Temperature/power snapshot and behavior during tests |
| `other` | Other | Platform and miscellaneous context |

---

## Established engines used

HBSS labels every result with its `Origin`: `recognized open-source`, `HBSS fallback`, or `third-party (opt-in)`.

**AUTO-capable — usable via `--download-benchmarks` (explicit opt-in, pinned + SHA-256 verified):**

| Engine | Area | Notes |
|---|---|---|
| Phoronix Test Suite | CPU/system harness | GPLv3; curated free tests only; batch/offline mode so results are never uploaded |
| Blender Benchmark (Cycles) | CPU + GPU rendering | GPL software, CC0 scenes; official SHA-256 manifests; offline mode; large asset needs `--allow-large-downloads` |
| 7-Zip (`7zz b`) | CPU compression | LGPL standalone console build; small download |
| fio | Storage | GPLv2; official SHA-256 release assets; temporary-file jobs **only**, never a raw device |
| Microsoft DiskSpd | Storage (Windows) | MIT, CLI, upstream SHA-256; primary automated Windows storage engine |

**DETECT-IF-INSTALLED — used only when already present and license permits:** sysbench, y-cruncher, ioping, OpenSSL `speed`, iperf3, clpeak.

**SKIP / UNRELIABLE:** lmbench (result-publication restrictions), STREAM as a *download* (HBSS instead compiles bundled pinned source locally — see below), Intel MLC (requires root/MSR access), RAMspeed (obsolete), CrystalDiskMark (GUI-only, UAC self-elevation, no usable CLI — detected but **not** executed), and NPU benchmark suites (no standardized, legally downloadable portable option).

**manual license required:** Geekbench 6 CPU/Compute and Cinebench are **detected only**. They are never auto-downloaded, redistributed, or executed unless you independently installed them, pass `--use-installed-benchmarks`, and confirm the license permits it. Geekbench's free tier **requires result uploads**, which HBSS will not do without informed, explicit consent.

**STREAM (memory bandwidth):** HBSS bundles pinned STREAM source, verifies its SHA-256, and compiles it at runtime with an existing `cc` / `clang` / `gcc` strictly inside the temp directory, deleting all artifacts afterward. The report records version, source SHA-256, compiler and version, flags, array size, total memory, thread count, per-kernel results, and validation status. Standard STREAM run rules (dataset ≳ 4× last-level cache) are followed when claiming a standard result; if limits force a smaller dataset it is labeled **`STREAM-derived (reduced dataset)`** — never presented as official STREAM. If no compiler is present, HBSS skips STREAM with a reason and never installs one. Quick mode skips compilation. HBSS's pointer-chasing latency test is a custom microbenchmark and is explicitly **not** standardized.

Primary-source licensing findings behind these decisions are in **`docs/RESEARCH.md`**.

---

## OS-specific benchmarks

- **Linux:** self-contained HBSS CPU/memory/storage microbenchmarks; `/proc` + `/sys` inventory; optional installed `sysbench`, `ioping`, `openssl speed`, `iperf3`, `y-cruncher`; opted-in Phoronix, Blender, 7-Zip, fio. Intel MLC and lmbench are never used; `powermetrics` does not apply.
- **Windows 10+ (PowerShell 5.1):** WMI/CIM (`Get-CimInstance`, `Get-PhysicalDisk`) inventory; .NET/PowerShell CPU, memory, and temp-file storage fallbacks; opted-in Microsoft DiskSpd (primary storage engine), Blender, 7-Zip, and fio (MSI extracted into temp, never installed). Geekbench, Cinebench, and CrystalDiskMark are detected only.
- **macOS (Intel and Apple Silicon):** `system_profiler` / `sysctl` / `ioreg` inventory; bundled/compiled microbenchmarks; opted-in Blender (Cycles via Metal), 7-Zip, fio, Phoronix; system `openssl` if installed. `powermetrics` is skipped because it requires root and its estimates are unsuitable for comparison. y-cruncher/Intel MLC are unavailable on ARM.

No GPU or NPU performance number is ever fabricated: if no engine is present, the report states "not measured / engine unavailable."

---

## What each benchmark measures

| Benchmark | Measures |
|---|---|
| CPU single / multi | Sustained integer and floating-point work over a fixed iteration budget; multi-core scaling vs. single-core |
| CPU scaling | Throughput as thread count increases (efficiency curve) |
| GPU render/compute | Time to complete a fixed Cycles render scene on CPU or GPU backend |
| Memory bandwidth | Sustained read/write/copy rates over a sized array (STREAM kernels or HBSS fallback) |
| Memory latency | Pointer-chasing dependency-chain latency (HBSS custom microbenchmark, not standardized) |
| Storage sequential | Sustained read/write throughput on a temporary file |
| Storage random | Random read/write IOPS and latency at fixed queue depth on a temporary file |
| Crypto | AES-GCM and common hash throughput via installed `openssl speed` |
| Network | TCP throughput on loopback (Full) or between the local host and an explicitly supplied `--endpoint` |
| Thermals | Temperature/power source snapshot before and during tests to characterize throttling behavior |

---

## What each benchmark does NOT measure

- **No raw-device performance.** Storage results include the filesystem and the OS I/O stack; they are not raw-disk measurements. No raw disks are ever touched.
- **No sustained/endurance testing.** Tests are short and time-bounded; they do not measure NAND endurance, thermal steady-state over hours, or degradation.
- **No cross-machine comparability guarantee.** Results depend on OS, kernel/driver versions, running background load, and CPU governor. They are indicative, not certification-grade.
- **No proprietary "score."** HBSS does not produce Geekbench/Cinebench-style single numbers unless such a tool was independently run by you and explicitly attributed.
- **No GPU/NPU result without an engine.** Detection is not a performance measurement.
- **No power/efficiency figures.** `powermetrics`-style power estimates are not used (they require root and are not comparable).
- **Not a security audit or stability test.** HBSS does not probe vulnerabilities, stress components to failure, or attempt to overclock/undervolt.

---

## Downloads and temporary execution behavior

**Default = store-first hybrid.** HBSS downloads **nothing** from third parties by default. It detects what is installed, uses lightweight self-contained implementations, and — where native functionality is required — prefers small, prebuilt HBSS release assets. Detection is immediate and benchmarks are short. No admin, no install, no config.

- `--download-benchmarks` opts in to **pinned official downloads only** (7-Zip `7zz b`, fio, Blender Benchmark, Microsoft DiskSpd, Phoronix Test Suite), each with **SHA-256 verification** into a temporary directory. Sources are trusted official locations: no unpinned `latest`, no unverified mirrors. Downloads are bounded in size and time.
- `--no-downloads` forces no downloads even when other flags would permit them (it always wins).
- `--allow-large-downloads` additionally permits large assets such as Blender; otherwise such downloads are skipped.
- Downloaded engines execute **from the temp directory** and are deleted on normal termination. Nothing is installed system-wide.
- Proprietary tools are **never** downloaded or redistributed by HBSS.

---

## Security model

- **Read-only detection.** Inventory uses unprivileged OS interfaces. HBSS never elevates to sudo/admin.
- **No persistence.** No services, scheduled tasks, startup entries, registry/system changes, or configuration writes.
- **Bounded execution.** Per-test timeouts, file-size caps, bounded download sizes, and no unlimited loops.
- **SHA-256 verified downloads.** Pinned versions and digests only (see above).
- **License-aware.** "Detected" never means "executed." EULAs are never auto-accepted; no activation, online submission, or GUI consent is bypassed.
- **Network isolation by default.** No external traffic unless you pass **both** `--allow-network` **and** an explicit `--endpoint <host>`. Loopback tests run only in Full.
- **Temp-only, cleaned up.** All working files live in a temp directory that is removed on normal exit.

---

## Trace and privacy

HBSS is designed to leave no trace:

> HBSS intentionally creates no persistent application files, telemetry, or configuration changes. Temporary artifacts are cleaned up on normal termination. Unexpected power loss or OS-level logging may fall outside its control.

Additional accuracy notes:

- HBSS performs **no telemetry and no result uploads** on its own. There is no analytics, no phone-home, and no automatic submission to any service.
- **Third-party engines may have their own network behavior.** For example, **Geekbench's free tier requires result uploads** to Primate Labs, and some suites can upload to public databases. HBSS runs engines in offline/batch mode and never auto-uploads. If you choose to run a proprietary tool, any upload is your responsibility and requires informed consent.
- **OS-level logging** (for example journald/auditd, Windows Event Log, or unified logging on macOS) may still record that processes ran. HBSS neither suppresses nor depends on such logging.

---

## Safety restrictions

HBSS will not, under any profile or flag:

- request sudo/admin or elevated privileges;
- change firmware/BIOS settings, voltage, overclocking, fan curves, or power limits;
- modify the registry, system configuration, services, or persistence mechanisms;
- install or remove packages or software;
- write to raw disks, format, trim, repartition, or mount/unmount volumes;
- run destructive tests, unlimited loops, memory-exhaustion tests, or deliberate overheating;
- exceed per-test timeouts or storage-file caps;
- generate external network traffic without explicit opt-in and an explicit endpoint;
- transmit results or telemetry without informed consent.

Long tests are skipped on battery. Storage tests use a temporary file in the working volume only. By default only that volume is tested; `--all-drives` opts in to eligible **fixed local** volumes and skips network, removable, read-only, and low-free-space volumes. Reports always state that storage results include the filesystem and OS I/O stack and are **not raw-device performance**.

---

## Benchmark methodology

1. **Detect** hardware through OS interfaces; record OS, architecture, host, and profile overrides.
2. **Plan** a category set from the profile and `--only` / `--skip`, applying safety gates (battery, privileges, availability, license).
3. **Acquire** engines according to the download policy — store-first by default; pinned, SHA-256-verified official assets only when opted in.
4. **Run** each test inside its hard timeout and file-size cap, using a temp file for storage and offline/batch mode for engines.
5. **Record** engine name, version, workload, thread count, dataset size, duration, result, unit, and `Origin` for every test; record a reason for every skip.
6. **Clean up** the temp directory on normal termination and print the report.

Results are meant for **relative, same-machine, same-configuration comparison**. Always compare like with like: same profile, same engine and version, same workload, and similar background load. For STREAM specifically, a standard result requires a dataset ≳ 4× last-level cache; smaller datasets are labeled `STREAM-derived (reduced dataset)`.

---

## Known limitations

- Results are not certification-grade and are not guaranteed comparable across different OSes, kernels, drivers, or machines.
- GPU and NPU performance depend on engine availability; many systems will report "not measured / engine unavailable."
- Cycles device detection can be fragile in headless VMs; software-rendering fallbacks may be reported distinctly.
- Temperature sensors are not present or not readable on all hardware; thermal data may be partial.
- STREAM compilation requires an existing compiler; Quick mode never compiles it, and a reduced dataset is labeled accordingly.
- CrystalDiskMark and other GUI-only tools are detected but cannot be automated.
- The official pages for some engines do not publish SHA-256 digests; HBSS pins its own verified hashes and will refuse a download whose digest does not match.
- Version numbers and download URLs drift over time; pinned versions are recorded in `docs/RESEARCH.md` and updated deliberately.

---

## Example output

Below is an abbreviated illustration of the console output format. Values are examples only.

```text
HBSS 1.0.0 — Hardware Benchmark Suite Script
Profile: Standard (cap 5-10 min)   OS: Linux 6.x   Arch: x86_64

[detect ] CPU     : Example CPU 8C/16T
[detect ] Memory  : 32 GiB
[detect ] GPU     : Example GPU (driver 5xx)

[run    ] cpu.single        HBSS fallback       20.4 s  1,842 Mops   Mops
[run    ] cpu.multi         HBSS fallback       19.8 s  11,905 Mops  Mops
[run    ] memory.bandwidth  STREAM-derived (reduced dataset) ...
[skip   ] gpu.render         reason: no eligible engine (use --download-benchmarks --allow-large-downloads)
[skip   ] npu.inference      reason: no standardized portable NPU benchmark
[cleanup] temporary artifacts removed

Report written to stdout. 12 completed, 5 skipped, 0 failed.
```

See [`SAMPLE_REPORT.md`](SAMPLE_REPORT.md) for a complete, fully structured example report (clearly marked as illustrative).

---

## Ethics

HBSS is intended for **personal evaluation of hardware you own or are authorized to test**, and for **legitimate inspection of display units** in retail or demonstration settings. When testing hardware that is not yours:

- **Respect store and venue policies** and any posted rules; comply with staff instructions.
- **Get permission** from the owner or responsible party before benchmarking.
- **Do not circumvent or interfere** with security controls, kiosk modes, management software, or other users' activity.
- **Do not perform stress, destructive, or disruptive testing**, and do not deliberately overheat, exhaust batteries, or degrade hardware.
- Keep tests short and within the profile limits; stop if asked.

Respect the licenses of third-party tools and the privacy of others. Do not use HBSS to exfiltrate data, identify individuals, or bypass access controls.

---

## Disclaimer

HBSS is provided **"as is"**, without warranty of any kind, express or implied. Benchmark results are approximate and depend on many factors; they are provided for informational purposes only and may not reflect real-world performance. HBSS is not affiliated with or endorsed by any benchmark vendor. Trademarks belong to their respective owners. Use of third-party engines is governed by their own licenses and terms, and may require accepting a EULA or uploading results — HBSS does not do so on your behalf. You are responsible for complying with all applicable laws, licenses, and venue policies when using this tool.

---

## License

GPL-3.0-or-later. See LICENSE.

HBSS is free software licensed under the GNU General Public License, version 3 or (at your option) any later version. If you distribute HBSS — especially in binary or bundled form — you have GPLv3 obligations, including providing the **Corresponding Source** (or a valid written offer) and preserving license and copyright notices. The GPL grants no right to redistribute **proprietary third-party benchmark binaries** (for example Geekbench or Cinebench) without the copyright holder's permission; each third-party license stands on its own. Primary-source licensing findings are documented in `docs/RESEARCH.md`.
