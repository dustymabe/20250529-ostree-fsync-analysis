# OSTree `fsync=false` Rebase Performance Analysis

**Date:** 2026-05-29
**Author:** Generated via coreos-assembler kola testing

## Summary

This analysis benchmarks the effect of setting `fsync=false` in the OSTree
repo config (`/sysroot/ostree/repo/config` `[core]` section) on the
performance of `rpm-ostree rebase` from an oci-archive.

Setting `fsync=false` instructs OSTree to skip `fsync()` calls when writing
objects during operations like pulls, rebases, and checkouts. This trades
crash safety for speed. See
[ostree.repo-config(5)](https://ostreedev.github.io/ostree/man/ostree.repo-config.html)
for details.

## Test Environment

| Parameter | Value |
|-----------|-------|
| Cloud provider | AWS |
| Instance type | `m8a.xlarge` (4 vCPU, 16 GB RAM, AMD EPYC) |
| Region | us-east-1 |
| Starting image | RHCOS AMI `ami-0368e7083557a9c5d` |
| Starting OS version | RHCOS `9.6.20251015-1` |
| Target OS version | RHCOS `9.6.20260401-0` |
| Rebase source | `https://dustymabe.fedorapeople.org/rhcos-9.6.20260401-0-ostree.x86_64.ociarchive` (1.26 GB) |
| Layers fetched | 50 ostree chunk layers (1.3 GB), 1 already present |
| Test framework | kola (coreos-assembler) with `--multiply 3 --parallel 3` |
| kola binary | Built from branch `dusty-buildfetch-decompress` (commit `4b19a749c`) |

## Test Procedure

Each test instance:

1. Boots RHCOS 9.6.20251015-1 from the AMI
2. (fsync=false variant only) Runs `ostree config --repo=/sysroot/ostree/repo set core.fsync false`, then stops `rpm-ostreed.service` to flush cached config
3. Downloads the RHCOS 9.6.20260401-0 oci-archive via `curl` (~1.26 GB)
4. Runs `rpm-ostree rebase ostree-unverified-image:oci-archive:/srv/fcos-stable.ociarchive`
5. Reboots via `autopkgtest-reboot`
6. Verifies the new version is booted

The test was run 3 times per variant (6 total AWS instances), all in parallel.

## Results

### Raw Data

#### Baseline (fsync=true, default)

| Run | curl download | rpm-ostree rebase | kola total |
|-----|---------------|-------------------|------------|
| 0   | 57.5s         | 35.8s             | 235.4s     |
| 1   | 61.8s         | 56.0s             | 1361.1s [1] |
| 2   | 55.9s         | ~46.6s [2]        | 250.9s     |

[1] Run 1 kola total inflated by an SSH connectivity flake that caused kola
    to destroy and re-provision the instance (~18 minutes wasted). The actual
    test execution time on the second instance was normal.

[2] Run 2 rebase time estimated from journal timestamps
    (`Txn Rebase ... successful` at 20:33:59.62 minus command start at
    20:33:13.0 = 46.6s). The `time` shell builtin output was lost in the
    systemd journal because the reboot happened before the journal flushed.

#### fsync=false

| Run | curl download | rpm-ostree rebase | kola total |
|-----|---------------|-------------------|------------|
| 0   | 41.9s         | 28.1s             | 206.5s     |
| 1   | 41.2s         | 19.1s             | 200.9s     |
| 2   | 43.4s         | 27.7s             | 200.5s     |

### Averages

| Metric              | fsync=true (avg) | fsync=false (avg) | Speedup |
|---------------------|------------------|-------------------|---------|
| curl download       | 58.4s            | 42.2s             | 1.4x    |
| **rpm-ostree rebase** | **46.1s**      | **24.9s**         | **1.9x** |
| kola total [3]      | 243.2s           | 202.6s            | 1.2x    |

[3] Baseline kola total averaged over runs 0 and 2 only (excluding run 1
    which had the SSH flake).

### Analysis

- **rpm-ostree rebase is ~1.9x faster with `fsync=false`**: average 46.1s
  vs 24.9s, saving ~21 seconds per rebase of 1.3 GB across 50 ostree chunk
  layers.

- **curl download times differ between the two batches** (58s baseline vs
  42s fsync=false). This is unrelated to fsync -- it reflects network
  variability to `fedorapeople.org`. The two batches ran at different times
  (~20:32 vs ~20:58 UTC).

- **The rebase speedup is consistent across all runs**: all 3 fsync=false
  runs clustered at 19-28s, while all 3 baseline runs were 36-56s.

## Earlier FCOS Single-Run Results

A preliminary single-run comparison was also done on FCOS (not RHCOS):

| Parameter | Value |
|-----------|-------|
| Starting image | FCOS AMI `ami-081fb3e56b87e0760` |
| Starting version | FCOS `43.20251024.3.0` (earliest F43 stable) |
| Target | `quay.io/fedora/fedora-coreos:stable` -> `44.20260510.3.1` |
| Layers | 65 ostree chunks (1.0 GB) + 1 custom (179 bytes) |

| Metric | fsync=true | fsync=false | Speedup |
|--------|------------|-------------|---------|
| skopeo copy | 20.4s | 15.0s | 1.4x |
| **rpm-ostree rebase** | **61.9s** | **25.9s** | **2.4x** |
| kola total | 309.4s | 164.1s | 1.9x |

## Directory Structure

```
logs/
  fcos-baseline/           # FCOS single-run, fsync=true
  fcos-fsync-false/        # FCOS single-run, fsync=false
  rhcos-baseline/          # RHCOS 3x runs, fsync=true
  rhcos-fsync-false/       # RHCOS 3x runs, fsync=false
test/
  test.sh                  # The kola external test used
  fsync-false.bu           # Butane config to enable fsync=false variant
```

Each log directory preserves the kola output structure:
`<test-name>/<instance-id>/{journal.txt,console.txt,...}`
