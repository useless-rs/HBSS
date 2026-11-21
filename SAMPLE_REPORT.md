# Hardware Benchmark Suite Report

> [!WARNING]
> **ILLUSTRATIVE / SIMULATED DOCUMENT — NOT REAL DATA.**
> This file is a **fictional example** created to demonstrate HBSS report structure and formatting. Every measurement, identifier, version, status, and result below is **simulated and tagged `(illustrative)`**. It was not produced by running HBSS on any machine, and no value in this document should be treated as a real measurement or as a claim about any hardware, software, or vendor.

---

## Run Summary

| Field | Value |
|---|---|
| Profile | `standard` (illustrative) |
| Started (UTC) | `2026-11-21T18:04:11Z` (illustrative) |
| Total duration | `7 min 42 s` (illustrative) |
| Tests completed | `12` (illustrative) |
| Tests skipped | `5` (illustrative) |
| Tests failed | `0` (illustrative) |
| OS | `Example Linux 6.8.0` (illustrative) |
| Architecture | `x86_64` (illustrative) |
| Host | `example-host` (illustrative) |
| Profile overrides | `--only cpu,gpu,memory,storage,crypto` (illustrative) |

This is a **Standard** profile run (5–10 minute cap). No third-party downloads were performed: all results below come from HBSS self-contained implementations or engines detected as already installed. Network and temperature extensions were outside the selected categories.

---

## System Overview

| Component | Detail |
|---|---|
| CPU model | `Example Processor 8C/16T @ 3.60 GHz` (illustrative) |
| CPU topology | `1 socket, 8 physical cores, 16 logical threads` (illustrative) |
| CPU caches | `L1 512 KiB / L2 4 MiB / L3 16 MiB` (illustrative) |
| Memory | `32 GiB DDR5` (illustrative) |
| GPU | `Example GPU, 8 GiB VRAM, driver 550` (illustrative) |
| Primary storage | `Example NVMe 512 GiB, ext4` (illustrative) |
| Power source | `AC` (illustrative) |
| Firmware | `Example BIOS 2.1` (illustrative) |

Hardware facts above were obtained from read-only OS inventory interfaces. They are simulated values shown for illustration only.

---

## CPU

Single-core, multi-core, and scaling behavior were measured with a fixed-iteration integer/float workload. Scaling efficiency is the multi-core throughput divided by single-core throughput, normalized by thread count.

| Metric | Workload | Result | Unit | Origin |
|---|---|---|---|---|
| Single-core throughput | integer + float mix, 1 thread | `1,842 (illustrative)` | `Mops` | HBSS fallback |
| Multi-core throughput | integer + float mix, 16 threads | `11,905 (illustrative)` | `Mops` | HBSS fallback |
| Scaling efficiency | 16 threads vs 1 thread | `40.4 (illustrative)` | `%` | HBSS fallback |

Interpretation (illustrative): multi-core throughput rose with thread count but scaled below the ideal linear factor, consistent with memory-bound portions of the workload. This is a synthetic relative indicator, not a cross-platform score.

---

## GPU

The GPU was identified through OS inventory. A short Cycles render benchmark completed using an engine detected as already installed; the proprietary Geekbench Compute path was not used.

| Metric | Engine | Workload | Result | Unit | Origin |
|---|---|---|---|---|---|
| Cycles CPU render | Blender Benchmark (detected) | bundled scene, CPU device, low samples | `28.6 (illustrative)` | `s` (lower is better) | recognized open-source |
| Cycles GPU render | Blender Benchmark (detected) | bundled scene, GPU device, low samples | `4.9 (illustrative)` | `s` (lower is better) | recognized open-source |

GPU compute capability is reported only where an actual engine executed; inventory detection alone is never presented as a performance result. Proprietary GPU suites were skipped (see [Skipped Tests](#skipped-tests)).

---

## Memory

Bandwidth was measured with locally compiled STREAM kernels; because the working set was constrained by the Standard profile, the result is explicitly labeled `STREAM-derived (reduced dataset)`. Latency came from HBSS's custom pointer-chasing microbenchmark, which is **not** a standardized metric.

| Metric | Engine | Result | Unit | Origin |
|---|---|---|---|---|
| Copy bandwidth | STREAM-derived (reduced dataset) | `14.2 (illustrative)` | `GiB/s` | HBSS fallback |
| Triad bandwidth | STREAM-derived (reduced dataset) | `16.8 (illustrative)` | `GiB/s` | HBSS fallback |
| Pointer-chasing latency | HBSS custom microbenchmark | `88.3 (illustrative)` | `ns` | HBSS fallback |

STREAM metadata (illustrative): compiler `Example CC 14.2`, source SHA-256 pinned and verified, flags `-O3 -fopenmp`, array size `64 MiB`, total memory `32 GiB`, threads `16`, validation `passed`. Because the dataset was smaller than ~4× last-level cache, these figures must not be presented as an official STREAM result.

---

## Storage

All storage tests used a **temporary test file** in the working volume. Results therefore include the filesystem and the OS I/O stack and are **not raw-device performance**. No raw disks, formatting, trim, or repartitioning were performed. Default testing covered only the temp directory's backing volume; `--all-drives` was not used.

| Metric | Engine | Workload | Result | Unit | Origin |
|---|---|---|---|---|---|
| Sequential read | fio (detected) | 1 MiB blocks, queue depth 4 | `2,140 (illustrative)` | `MiB/s` | recognized open-source |
| Sequential write | fio (detected) | 1 MiB blocks, queue depth 4 | `1,760 (illustrative)` | `MiB/s` | recognized open-source |
| Random read | fio (detected) | 4 KiB blocks, queue depth 32 | `182,000 (illustrative)` | `IOPS` | recognized open-source |
| Random write | fio (detected) | 4 KiB blocks, queue depth 32 | `96,500 (illustrative)` | `IOPS` | recognized open-source |

Test-file cap for the Standard profile was `1 GiB (illustrative)`. On Windows the equivalent automated engine would be Microsoft DiskSpd (MIT, SHA-256 verified); CrystalDiskMark is detected only and never executed because it is GUI-only with UAC self-elevation and no usable CLI.

---

## Network

No external network test was performed. External iperf3 requires **both** `--allow-network` and an explicit `--endpoint <host>`; neither was supplied, and loopback testing is reserved for the Full profile. Interface status below is inventory only (illustrative).

| Interface | Link | Address | External test |
|---|---|---|---|
| `eth0` (illustrative) | `1 Gb/s` (illustrative) | `192.0.2.10/24` (illustrative) | not run — no `--endpoint` (illustrative) |
| `lo` (illustrative) | `loopback` (illustrative) | `127.0.0.1/8` (illustrative) | not run — Full profile only (illustrative) |

HBSS generated no external traffic and performed no internet speed test, telemetry, or result upload.

---

## AI / NPU

No NPU performance result is reported. NPU presence and name were read from inventory only, and no standardized, legally downloadable, portable NPU benchmark exists. Any NPU number would require a proprietary third-party tool the user installed themselves and would be explicitly attributed to that tool.

| Item | Status |
|---|---|
| NPU inventory | `none reported (illustrative)` |
| NPU performance | `not measured — no standardized portable engine (illustrative)` |

---

## Other Hardware

| Item | Detail |
|---|---|
| Audio | `Example audio controller (illustrative)` |
| USB controllers | `2 (illustrative)` |
| Displays | `1 × 2560×1440 @ 60 Hz (illustrative)` |
| Battery | `not present / AC powered (illustrative)` |

These entries provide context only and were not benchmarked.

---

## Thermals and Performance Behavior

No extended thermal soak was run under this profile, but a lightweight temperature snapshot was captured before and after the CPU workload to illustrate throttling behavior. Values are simulated and indicative only.

| Sensor | Before | After | Unit |
|---|---|---|---|
| CPU package (illustrative) | `38 (illustrative)` | `71 (illustrative)` | `°C` |
| GPU (illustrative) | `34 (illustrative)` | `52 (illustrative)` | `°C` |

A rise under sustained load is normal; HBSS does not attempt to force or sustain high temperatures, and thermal readings are not comparable across machines or sensors.

---

## Benchmark Results

This is the canonical result table. `Origin` is one of `recognized open-source`, `HBSS fallback`, or `third-party (opt-in)`.

| Benchmark | Category | Engine | Version | Workload | Threads | Dataset | Duration | Result | Unit | Origin | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| cpu.single | cpu | HBSS mix | 1.0.0 | int+float, 1 thread | `1 (illustrative)` | fixed iterations (illustrative) | `20.4 s (illustrative)` | `1,842 (illustrative)` | `Mops` | HBSS fallback | relative indicator |
| cpu.multi | cpu | HBSS mix | 1.0.0 | int+float, all cores | `16 (illustrative)` | fixed iterations (illustrative) | `19.8 s (illustrative)` | `11,905 (illustrative)` | `Mops` | HBSS fallback | relative indicator |
| cpu.scaling | cpu | HBSS mix | 1.0.0 | thread sweep | `1–16 (illustrative)` | fixed iterations (illustrative) | `61.0 s (illustrative)` | `40.4 (illustrative)` | `%` | HBSS fallback | efficiency vs 1 thread |
| gpu.cycles.cpu | gpu | Blender Benchmark | `4.x (illustrative)` | bundled scene, CPU | `16 (illustrative)` | low samples (illustrative) | `28.6 s (illustrative)` | `28.6 (illustrative)` | `s` | recognized open-source | lower is better; detected engine |
| gpu.cycles.gpu | gpu | Blender Benchmark | `4.x (illustrative)` | bundled scene, GPU | `n/a (illustrative)` | low samples (illustrative) | `4.9 s (illustrative)` | `4.9 (illustrative)` | `s` | recognized open-source | lower is better; offline mode |
| memory.copy | memory | STREAM-derived | source pinned | copy kernel | `16 (illustrative)` | `64 MiB (illustrative)` | `30.0 s (illustrative)` | `14.2 (illustrative)` | `GiB/s` | HBSS fallback | reduced dataset |
| memory.triad | memory | STREAM-derived | source pinned | triad kernel | `16 (illustrative)` | `64 MiB (illustrative)` | `30.0 s (illustrative)` | `16.8 (illustrative)` | `GiB/s` | HBSS fallback | reduced dataset |
| memory.latency | memory | HBSS pointer-chase | 1.0.0 | dependent loads | `1 (illustrative)` | `64 MiB (illustrative)` | `10.0 s (illustrative)` | `88.3 (illustrative)` | `ns` | HBSS fallback | custom, not standardized |
| storage.seq.read | storage | fio | `3.x (illustrative)` | 1 MiB, QD4 | `4 (illustrative)` | `1 GiB (illustrative)` | `45.0 s (illustrative)` | `2,140 (illustrative)` | `MiB/s` | recognized open-source | temp file only |
| storage.seq.write | storage | fio | `3.x (illustrative)` | 1 MiB, QD4 | `4 (illustrative)` | `1 GiB (illustrative)` | `45.0 s (illustrative)` | `1,760 (illustrative)` | `MiB/s` | recognized open-source | temp file only |
| storage.rand.read | storage | fio | `3.x (illustrative)` | 4 KiB, QD32 | `32 (illustrative)` | `1 GiB (illustrative)` | `45.0 s (illustrative)` | `182,000 (illustrative)` | `IOPS` | recognized open-source | temp file only |
| storage.rand.write | storage | fio | `3.x (illustrative)` | 4 KiB, QD32 | `32 (illustrative)` | `1 GiB (illustrative)` | `45.0 s (illustrative)` | `96,500 (illustrative)` | `IOPS` | recognized open-source | temp file only |
| crypto.aes | crypto | OpenSSL speed | `3.x (illustrative)` | aes-128-gcm | `8 (illustrative)` | 16 KiB buffers (illustrative) | `30.0 s (illustrative)` | `1,480 (illustrative)` | `MiB/s` | recognized open-source | detected system engine |
| crypto.sha256 | crypto | OpenSSL speed | `3.x (illustrative)` | sha256 | `8 (illustrative)` | 16 KiB buffers (illustrative) | `30.0 s (illustrative)` | `620 (illustrative)` | `MiB/s` | recognized open-source | detected system engine |

All values in this table are illustrative. Durations shown are representative per-test caps, not measured timings from a real run.

---

## Methodology

1. **Detection.** Hardware inventory was gathered from read-only OS interfaces; no elevation or download was used.
2. **Planning.** The Standard profile and `--only cpu,gpu,memory,storage,crypto` selected the category set; safety gates (power source, privileges, engine availability, license) were applied.
3. **Acquisition.** No third-party downloads were performed. Engines used were either HBSS self-contained implementations or tools detected as already installed, run in offline/batch mode.
4. **Execution.** Each test ran inside its hard per-test timeout and file-size cap; storage used a temporary file only; offline/batch mode prevented result uploads.
5. **Recording.** Engine name, version, workload, thread count, dataset, duration, result, unit, and `Origin` were captured for each completed test, with an explicit reason for each skip.
6. **Cleanup.** Temporary artifacts were removed on normal termination.

Results are intended for **relative, same-machine, same-configuration comparison**. Compare like with like: same profile, engine and version, workload, and similar background load. For STREAM, a standard result requires a dataset of roughly 4× last-level cache or larger; the reduced dataset used here is labeled `STREAM-derived (reduced dataset)` and is not an official STREAM result. The pointer-chasing latency figure is an HBSS custom microbenchmark, explicitly not standardized.

---

## Trace and Privacy

> HBSS intentionally creates no persistent application files, telemetry, or configuration changes. Temporary artifacts are cleaned up on normal termination. Unexpected power loss or OS-level logging may fall outside its control.

HBSS performed no telemetry and no result uploads. Third-party engines may still have their own network behavior: for example, **Geekbench's free tier requires result uploads**, and some suites can submit to public databases; HBSS runs engines in offline/batch mode and never auto-uploads. OS-level logging (such as journald/auditd, Windows Event Log, or macOS unified logging) may still record that processes ran; HBSS neither suppresses nor depends on such logging. No proprietary tool was executed in this illustrative run.

---

## Skipped Tests

| Benchmark | Category | Reason | Profile |
|---|---|---|---|
| gpu.geekbench.compute | gpu | Proprietary; needs manual license and free tier requires result uploads | `standard (illustrative)` |
| npu.inference | npu | No standardized, legally downloadable portable NPU benchmark | `standard (illustrative)` |
| network.external | network | Requires both `--allow-network` and explicit `--endpoint <host>` | `standard (illustrative)` |
| network.loopback | network | Loopback test reserved for Full profile | `standard (illustrative)` |
| storage.all-drives | storage | Requires opt-in `--all-drives`; only temp volume tested by default | `standard (illustrative)` |

---

## License

GPL-3.0-or-later. See LICENSE.

HBSS is free software under the GNU General Public License, version 3 or later. Redistributors have GPLv3 obligations, including providing the Corresponding Source and preserving license notices. The GPL does not grant permission to redistribute proprietary third-party benchmark binaries without their copyright holders' permission. Primary-source licensing findings are in `docs/RESEARCH.md`.

---

## Caveats

- This entire document is **simulated and illustrative**; no value here is a real measurement.
- Results are approximate and depend on OS, kernel, driver versions, background load, and CPU governor; they are not certification-grade.
- Storage figures include the filesystem and OS I/O stack and are **not raw-device performance**.
- STREAM results here use a reduced dataset and are labeled `STREAM-derived (reduced dataset)`; they are not official STREAM results.
- The pointer-chasing latency figure is a custom HBSS microbenchmark and is not a standardized metric.
- GPU and NPU performance are reported only where a real engine executed; detection alone is never a result.
- Cross-machine comparisons are unreliable; compare only like with like.
- Temperatures are sensor- and platform-dependent and are not comparable across systems.
- Third-party engine usage is governed by each tool's own license and may require accepting a EULA or uploading results; HBSS does not do so on your behalf.
