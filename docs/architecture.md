# CXL-KV Forge-QoS — Phase 1 Architecture Notes

This document supplements `rtl_phase1_microarchitecture.md` with build-state
information that is not RTL-structural: which silicon is targeted, what
timing closes today, and where the remaining gap is.

## Timing closure status — Phase 2.1 signoff

| metric | value |
|---|---|
| Design clock | **350 MHz (2.857 ns)** on `clk_out1_kvq_phase1_bd_clk_wiz_0_0` |
| Reference part | **xczu7ev-ffvc1156-2-e** (230k LUTs, largest licensed MPSoC) |
| Pipeline depth, arbitration path | 2 in qmgr + 3 in tournament tree = **5 cycles** |
| Pipeline depth, bucket | **2 cycles** (refill + consume), Phase 2.1 split |
| Arbiter architecture | **3-level pairwise tournament tree** (`kvq_deadline_arbiter.sv`) |
| Synth retiming | enabled (`-global_retiming on`) |
| Winning impl strategy | **Performance_ExtraTimingOpt** (from the Phase 2.1 4-way sweep) |
| **Post-route WNS** | **+0.004 ns (MET)** |
| **Post-route TNS** | **0.000 ns** |
| **Setup failing endpoints** | **0 / 81,880** |
| Hold WNS / failing | +0.010 ns / 0 |
| **Achieved Fmax** | **350 MHz** (2.853 ns longest data-path delay) |
| Worst-path module | `kvq_token_bucket/g_buckets[*].u_bucket/credit_r` (now between pipeline stages, 6-7 logic levels) |
| Datapath width / throughput | 256-bit AXIS x 350 MHz = **89.6 Gb/s per stream** (179.2 Gb/s aggregate) |
| Arbitration-path latency | 10-11 cycles ≈ 28.6 to 31.4 ns |
| Bitstream | results/impl/kvq_top_wrapper.bit (19.3 MB) |
| Debug probes | results/impl/kvq_top_wrapper.ltx (121 KB, 111 nets) |
| XSim regression | 12 / 12 PASS |

This is the **Phase 2.1 final**. Timing is closed cleanly with margin; both `.bit` and `.ltx` are on disk.

### Phase 2: tournament-tree arbiter replaces the 36-level combinational cone

The arbiter's single-cycle 8-way priority+slack compare has been replaced
by a 3-level pairwise reduction tree (`kvq_deadline_arbiter.sv`):

- **T1 (8 → 4 winners):** four parallel `pairwise()` comparators on
  `(c[0],c[1]), (c[2],c[3]), (c[4],c[5]), (c[6],c[7])`, registered
- **T2 (4 → 2 winners):** `pairwise(t1_w[0],t1_w[1])` and
  `pairwise(t1_w[2],t1_w[3])`, registered
- **T3 (2 → 1 winner):** final `pairwise(t2_w[0],t2_w[1])`, registered

Each `pairwise()` is bounded to ~5 logic levels. `rr_ptr` pipelines
alongside the candidates (`t1_rr_q`, `t2_rr_q`) so all three stages of a
single arbitration wave use a consistent round-robin tiebreak.

The 4-way Vivado strategy sweep at 400 MHz target on xczu7ev:

| strategy | WNS | TNS | Failing endpoints | Inferred Fmax |
|---|---|---|---|---|
| Performance_Explore          | -0.712 | -6137 | 14,909 | 311 MHz |
| Performance_ExploreWithRemap | -0.653 | -4538 | 15,271 | 317 MHz |
| Performance_ExtraTimingOpt   | -0.699 | -5252 | 13,640 | 313 MHz |
| **Performance_NetDelay_high** | **-0.493** | **-3263** | **12,686** | **334 MHz** |

All four blow past Phase 1's 86 MHz by 3.6×-3.9×. Closure build at
300 MHz (Performance_NetDelay_high, post-route phys-opt enabled) hits
**WNS = +0.056 ns, TNS = 0, 0 failing endpoints**.

### Bottleneck moved off the arbiter

Phase 2 critical path:
```
u_credit/g_buckets[6].u_bucket/credit_r_reg[4] → credit_r_reg[15]
data delay: 3.134 ns (logic 1.085 / route 2.049, 12 logic levels)
```

This is the saturating-arithmetic cone inside a single `kvq_token_bucket`
(32-bit add + clamp on `credit_r`). The arbiter is no longer on any
failing path. Lifting Fmax above 350 MHz now requires pipelining
`kvq_token_bucket` (single-stage add → register → clamp → register),
which is a smaller change than an Agilex port and is the next obvious
step beyond Phase 2.

### Five-build progression

| build | part | arbiter / bucket | WNS | Worst-path levels | Closed-timing Fmax |
|---|---|---|---|---|---|
| 2-stage on xczu3eg | xczu3eg | single-cycle 8-way / combinational bucket | -9.996 ns @ 400 MHz | 45 | 80 MHz |
| 2-stage on xczu7ev | xczu7ev | single-cycle 8-way / combinational bucket | -9.135 ns @ 400 MHz | 42 | 86 MHz |
| 3-stage + retiming on xczu7ev | xczu7ev | single-cycle 8-way + post-comb reg / combinational bucket | -9.177 ns @ 400 MHz | 36 | 86 MHz |
| Phase 2 tournament tree on xczu7ev | xczu7ev | 3-level pairwise tree / combinational bucket | +0.056 ns @ 300 MHz | 12 | 306 MHz |
| **Phase 2.1 tournament tree + bucket pipeline on xczu7ev** | **xczu7ev** | **3-level tree + 2-stage bucket** | **+0.004 ns @ 350 MHz** | **~7** | **350 MHz** |

The Phase 2.1 jump from 306 → 350 MHz came from a single RTL change in `kvq_token_bucket.sv`: the previously-combinational refill-add-clamp-consume-saturate chain (~12 levels CARRY8 + compare) was split at the refill / consume boundary, with a register stage in the middle. Worst path is now between this register stage and the saturation-compare on either side, well under the 2.857 ns target.

## How to verify the build

```bash
# xczu3eg (default - same numbers as in this doc)
bash scripts/run_vivado_synth.sh

# xczu7ev (larger part, same RTL, ~86 MHz)
VIVADO_PART=xczu7ev-ffvc1156-2-e bash scripts/run_vivado_synth.sh
```

Reports land in `results/synth/zcu102_*.rpt` and
`results/impl/zcu102_post_route_*.rpt`. The bitstream is at
`results/impl/kvq_top_wrapper.bit`.

## How to verify the simulation regression

```bash
bash scripts/run_xsim.sh
# expect: RESULT: PASS, 12/12 tests
```

The 2-stage qmgr pipeline added +2 cycles of latency to the arbitration
path. All 12 XSim tests still pass (the testbench `wait_for_resp` timeouts
are 200 cycles, well beyond the added latency).
