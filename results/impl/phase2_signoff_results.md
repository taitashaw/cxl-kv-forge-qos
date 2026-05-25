# Phase 2 signoff - tournament-tree arbiter on xczu7ev-ffvc1156-2-e

Build date: 2026-05-25
Vivado: 2025.2 (build 6299465)
RTL: 3-stage tournament-tree arbiter (`kvq_deadline_arbiter.sv` rewrite)
     + 2-stage qmgr pipeline (unchanged from Phase 1 stage-3 build)
Part: xczu7ev-ffvc1156-2-e
Winning strategy: **Performance_NetDelay_high**
Closure target: **300 MHz** (3.333 ns period) — 95% of strategy-sweep Fmax (334 MHz × 0.90 actually, see below)

## Headline — Phase 2 closure ACHIEVED

| metric | value |
|---|---|
| Design clock | 300 MHz (3.333 ns) on `clk_out1_kvq_phase1_bd_clk_wiz_0_0` |
| **Post-route WNS** | **+0.056 ns (MET)** |
| **Post-route TNS** | **0.000 ns** |
| **Setup failing endpoints** | **0 / 69,461** |
| Hold WNS | +0.010 ns (MET) |
| Pulse-width WNS | +0.167 ns (MET) |
| Logic levels on worst path | **12** (was 36 in Phase 1) |
| Worst-path data delay | 3.134 ns (logic 1.085 / route 2.049) |
| Achieved Fmax (at 300 MHz target) | **305.9 MHz** (3.277 ns longest path) |
| Bitstream | `results/impl/kvq_top_wrapper.bit` (19.3 MB) |

## Strategy sweep (at 400 MHz target, 2.500 ns period)

| strategy | WNS (ns) | TNS (ns) | Failing endpoints | Inferred Fmax (MHz) |
|---|---|---|---|---|
| Performance_Explore          | -0.712 | -6137.224 | 14,909 | 311.3 |
| Performance_ExploreWithRemap | -0.653 | -4537.681 | 15,271 | 317.2 |
| Performance_ExtraTimingOpt   | -0.699 | -5251.847 | 13,640 | 312.6 |
| **Performance_NetDelay_high** | **-0.493** | **-3262.907** | **12,686** | **334.1** |

All four strategies show **3.6× to 3.9× Fmax improvement** vs the 85.6 MHz Phase 1 baseline.
The arbiter cone is no longer the bottleneck on ANY of them.

## Worst path on the closure build (300 MHz, MET)

```
Source:      kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/u_credit/g_buckets[6].u_bucket/credit_r_reg[4]/C
Destination: kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/u_credit/g_buckets[6].u_bucket/credit_r_reg[15]/D
Data delay:  3.134 ns (logic 1.085 ns / route 2.049 ns)
Logic levels: 12 (CARRY8=8, LUT2=2, LUT5=2)
```

The worst path is now **inside `u_credit/g_buckets[*].u_bucket/credit_r`** — the
saturating-arithmetic cone of a single token bucket (32-bit add + clamp). This
is a carry-chain path through CARRY8 cells, fundamentally bounded by the
adder's natural latency. The arbiter is no longer on any failing path.

## Comparison vs Phase 1 final (single-cycle arbiter + 3-stage retiming)

| metric | Phase 1 final | **Phase 2 signoff** | delta |
|---|---|---|---|
| Design clock target | 400 MHz (-9.18 ns WNS) | **300 MHz (+0.056 ns WNS)** | **timing closed** |
| Logic levels (worst) | 36 | **12** | -66% |
| Logic delay (worst) | 3.606 ns | 1.085 ns | -70% |
| Route delay (worst) | 7.980 ns | 2.049 ns | -74% |
| Total path delay (worst) | 11.586 ns | **3.134 ns** | -73% |
| Failing endpoints | 21,085 | **0** | -100% |
| Bottleneck module | u_arb (combinational cone) | u_credit (token-bucket arith) | moved off arbiter |
| **Achieved Fmax** | **85.6 MHz** | **305.9 MHz** | **3.57× faster** |
| LUTs used | 18,640 | 18,110 | -2.8% |
| FFs used | 28,808 | 28,729 | -0.3% |

## Did the bottleneck move off the arbiter cone?

**Yes - completely.** Phase 1's 36-level arbiter cone is gone. Worst-path
source and destination are both inside `u_credit/g_buckets[6].u_bucket`,
12 logic levels deep through a CARRY8 adder chain. The tournament tree's
maximum combinational segment is now a single pairwise comparator (~5
levels), well under any per-pipe-stage timing budget.

## Fmax vs the 350 MHz "no-Agilex" threshold

| achieved Fmax | spec threshold | verdict |
|---|---|---|
| 305.9 MHz | ≥ 350 MHz | **below threshold** |

The achievable Fmax is **305.9 MHz**, which is below the 350 MHz threshold
beyond which "Agilex port is not needed for the headline number". So the
spec recommends Agilex 7 -3 grade for 400 MHz claims.

However, the next bottleneck is now well-localized to one module
(`kvq_token_bucket`), and a one-stage arithmetic pipeline on its saturating
add/clamp would likely lift the achievable Fmax above 350 MHz on the same
xczu7ev part. That's a smaller change than an Agilex port. **The Agilex
port is not the only path to ≥350 MHz.**

## Utilization on xczu7ev

| resource | used | available | util% |
|---|---|---|---|
| CLB LUTs | 18,110 | 230,400 | 7.86% |
| CLB Registers | 28,729 | 460,800 | 6.23% |
| Block RAM Tile | 8 | 312 | 2.56% |

Plenty of headroom for future per-module pipelining (token bucket, memory
engine state machine, response builder).

## Artifacts

| file | status |
|---|---|
| `results/impl/kvq_top_wrapper.bit` | OK (19.3 MB) |
| `results/impl/zcu102_post_route_timing.rpt` | OK (41 KB) |
| `results/impl/zcu102_post_route_util.rpt` | OK (13 KB) |
| `results/synth/zcu102_synth_util.rpt` | OK (11 KB) |
| `results/synth/zcu102_timing_summary.rpt` | OK |
| `results/impl/phase2_strategy_sweep.md` | OK |
| `results/impl/kvq_top_wrapper.ltx` | **MISSING** (see below) |

### .ltx gap

The closure build's `create_debug_core` step did insert 111 MARK_DEBUG
probes into the synthesized netlist, but a `save_constraints` after that
step was deliberately omitted from `closure_build.tcl` (to avoid stale
debug-net references poisoning future builds via `constraints.xdc`). As a
result, the impl run didn't see the debug core, and `write_debug_probes`
reported "No debug cores were found in this design".

**Workaround for HW Manager debug**: re-run with `save_constraints`
enabled in the synth-side debug-core block. This will write the debug net
list into `constraints.xdc` (which must then be either reset or guarded
before the next user-driven build). Estimated rebuild time: ~15 min.

The .ltx gap does NOT affect the bitstream's correctness or the timing
closure — it only affects hardware debug visibility via ChipScope. For
deployment without hardware probing, the current bitstream is sufficient.

## XSim regression

12/12 PASS with the tournament-tree arbiter. Test latencies shifted by
+2 cycles per request (vs Phase 1 final), absorbed by the 200-cycle
`wait_for_resp` window. No `expected_outputs/` CSV regeneration required;
the testbench checks status fields and hit/deadline_miss flags, not exact
cycle counts.
