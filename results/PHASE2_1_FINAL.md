# Phase 2.1 — project-level signoff

Closed-timing signoff for CXL-KV Forge-QoS on the largest Vivado-licensed
Zynq UltraScale+ MPSoC available in this install.

## Headline

| metric | value |
|---|---|
| Date | 2026-05-26 |
| Part | xczu7ev-ffvc1156-2-e |
| Design clock | **350 MHz** (clk_wiz_0 output, 2.857 ns period) |
| Post-route WNS (setup) | **+0.004 ns (MET)** |
| Post-route TNS (setup) | **0.000 ns** |
| Setup failing endpoints | **0 / 81,880** |
| Hold WNS / failing | +0.010 ns / 0 |
| Datapath width (AXIS) | 256 bits request, 256 bits response |
| Per-stream throughput | 256 b × 350 MHz / 1000 = **89.6 Gb/s** |
| Aggregate AXIS throughput | request + response = **179.2 Gb/s** |
| Arbitration-path latency | ~10-11 cycles ≈ **28.6 to 31.4 ns** |
| Synth retiming | enabled (`-global_retiming on`) |
| Winning impl strategy | **Performance_ExtraTimingOpt** |
| XSim regression | **12 / 12 PASS** |
| Bitstream | `results/impl/kvq_top_wrapper.bit` (19.3 MB) |
| Debug probes file | `results/impl/kvq_top_wrapper.ltx` (121 KB, 111 MARK_DEBUG nets) |

## What it took to get here

Five RTL/build progressions, each rooted in a measured worst-path issue:

| build | RTL change | Closed-timing Fmax |
|---|---|---|
| Phase 1, 2-stage qmgr on xczu3eg | + 2 pipeline stages in queue manager | 80 MHz |
| Phase 1, 2-stage qmgr on xczu7ev | same RTL, larger part | 86 MHz |
| Phase 1 final, 3-stage + retiming | + post-comb register at arbiter output, `retiming_backward=1` | 86 MHz |
| **Phase 2** | **arbiter rewrite: 3-level pairwise tournament tree** | **305.9 MHz** |
| **Phase 2.1** | **+ 2-stage pipeline in `kvq_token_bucket` (refill / consume split)** | **350 MHz** |

The two structural fixes (tournament tree at Phase 2, bucket pipeline at
Phase 2.1) drove a 4.4× Fmax improvement; the part swap and Vivado retiming
contributed only the marginal 80 → 86 MHz lift.

## Throughput vs the field — FPGA Fmax only

This row deliberately compares only on FPGA Fmax. The "Gb/s" column is
withheld in the comparison because the design classes (KV-cache QoS
controller vs reference accelerators in adjacent niches) don't share a
single throughput definition.

| project | FPGA Fmax (post-route) |
|---|---|
| CXL-KV Forge-QoS (this project, Phase 2.1) | **350 MHz on xczu7ev-2e** |
| CXL-SpecKV reference (external) | not run in this repo |
| own flashattn-style comparator (external) | not run in this repo |

The external comparator rows are left as placeholders — those projects
aren't bundled into this repository, so a side-by-side run on the same
xczu7ev part hasn't been performed. The signoff number that DOES exist
in this repo is **350 MHz**, verified by Vivado timing reports and a
loadable bitstream + debug probes file.

## Worst path on the closure build

The Phase 2.1 worst path lives in `u_credit/g_buckets[*].u_bucket`, between
the new pipeline register and the saturation comparator (~6-7 logic levels).
The Phase 2 critical path (12-level CARRY8 chain across credit_r[4] →
credit_r[15]) is gone. Detailed timing report is at
`results/impl/zcu102_post_route_timing.rpt`.

## What's NOT in this signoff

- **xczu9eg (ZCU102) closure.** That part is one tier above xczu7ev and
  remains license-blocked in this Vivado install. The same RTL on a
  licensed xczu9eg would likely close at the same Fmax with more area
  margin, but the run hasn't been executed.
- **Real CXL endpoint / PCIe hard IP / DDR or HBM controller / Linux
  driver.** All deliberately out of scope; see `docs/phase1_known_limitations.md`.
- **Phase 0 plot regeneration tied to Fmax.** The Phase 0 scheduler
  simulator (`sim/run_benchmark.py`) operates in microsecond workload
  time (`Request.arrival_us` / `service_us`), independent of the RTL
  clock period. Plots in `results/plots/` are workload-policy
  comparisons and remain valid at any RTL Fmax.

## Open Phase 3 future work (not required for project closure)

1. **Agilex 7 -3 speed grade port.** The -3 grade is ~40% faster than
   UltraScale+ -2 on equivalent paths; same RTL on Agilex would reach
   roughly 1.4 × 350 = ~490 MHz theoretical, though placement constraints
   and tooling differences will eat some of that. Not gating for the
   Phase 2.1 signoff.
2. **Real CXL endpoint integration** (Versal Premium / Agilex 7 R-Tile).
3. **Multi-outstanding memory engine** with per-request tracking table.
4. **Per-tenant counter banks and histogram support** (Phase 1 deferred).
5. **Full 45-test directed matrix** (Phase 1 deferred 33 tests).

## Artifacts

```
results/synth/zcu102_synth_util.rpt
results/synth/zcu102_timing_summary.rpt
results/impl/zcu102_post_route_util.rpt
results/impl/zcu102_post_route_timing.rpt
results/impl/kvq_top_wrapper.bit
results/impl/kvq_top_wrapper.ltx
results/rtl_sim/phase1_xsim_summary.csv  (12/12 PASS)
results/adversarial_w4_summary.csv
results/plots/{adversarial_w4_baseline_comparison,w4_fairness_per_tenant,w4_jains_index}.png
results/impl/phase2_strategy_sweep.md
```

## Reproducing

```bash
# Reset constraints if a previous build polluted them with debug refs.
git checkout HEAD -- vivado/constraints.xdc

# 1. Project + 4-strategy sweep at 400 MHz target on xczu7ev (writes the
#    .bit from the sweep winner, but no .ltx)
VIVADO_PART=xczu7ev-ffvc1156-2-e bash scripts/run_vivado_synth.sh

# 2. Final closure at 350 MHz with debug-probe insertion (writes both
#    the closed-timing .bit and the populated .ltx)
git checkout HEAD -- vivado/constraints.xdc          # reset again
env VIVADO_PART=xczu7ev-ffvc1156-2-e vivado \
  -mode batch -nojournal -nolog \
  -source vivado/closure_build.tcl
```

The `vivado/constraints.xdc` reset between steps is necessary because
`closure_build.tcl` uses `save_constraints` to persist debug-core
wiring into the project's active XDC, which would otherwise carry stale
debug-net references into the next clean rebuild.
