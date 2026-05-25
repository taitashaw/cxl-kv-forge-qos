# CXL-KV Forge-QoS — Phase 1 Architecture Notes

This document supplements `rtl_phase1_microarchitecture.md` with build-state
information that is not RTL-structural: which silicon is targeted, what
timing closes today, and where the remaining gap is.

## Timing closure status

| metric | value |
|---|---|
| Target frequency | 400 MHz (2.500 ns clk_wiz_0 output) |
| Reference part | **xczu7ev-ffvc1156-2-e** (230k LUTs, largest licensed MPSoC) |
| Pipeline stages on arbitration path | **3** |
| Stage 1 + 2 location | `kvq_per_tenant_queue_manager.sv` (`deq_req_r`, `deq_grant_r`) |
| Stage 3 location | `kvq_deadline_arbiter.sv` (`sel_valid_q`/`sel_req_q`/`sel_tid_q`/`deq_grant_q`, `retiming_backward=1`) |
| Synth retiming | enabled (`STEPS.SYNTH_DESIGN.ARGS.RETIMING true`) |
| phys_opt directive | `AggressiveExplore` |
| **Post-route WNS** | **-9.177 ns** |
| **Achieved Fmax** | **~85.6 MHz** (11.677 ns longest path) |
| Bitstream | results/impl/kvq_top_wrapper.bit (19.3 MB) |

### Why we are still at ~86 MHz and not 400 MHz

Retiming was active and effective at the level it operates on — the
synth log has 2,957 `_bret_` / retiming entries, FF count grew by 677,
and logic levels on the worst path dropped 42 → 36. But the **routing
delay** of ~8 ns between mid-cone register replicas and `rr_ptr_reg` is
the dominant term, and routing distance doesn't shrink with retiming.

The post-retiming critical path is:

```
u_arb/sel_req_q_reg[opcode][7]_bret_6_rep → u_arb/rr_ptr_reg[1]_rep
data delay: 11.586 ns (logic 3.606 ns / route 7.980 ns, 36 logic levels)
```

Both endpoints are now **inside** `u_arb` — the third pipeline stage
successfully decoupled the arbiter from the memory engine (no more
cross-module timing dependency), but the arbiter's internal compare-tree
+ mux structure is the architectural bottleneck.

### Three-build progression

| build | part | stages | WNS | Logic levels | Fmax | bottleneck |
|---|---|---|---|---|---|---|
| 2-stage on xczu3eg | xczu3eg | 2 | -9.996 ns | 45 | 80 MHz | u_arb → u_mem |
| 2-stage on xczu7ev | xczu7ev | 2 | -9.135 ns | 42 | 86 MHz | u_arb → u_mem |
| **3-stage + retiming on xczu7ev** | **xczu7ev** | **3** | **-9.177 ns** | **36** | **85.6 MHz** | **u_arb internal** |

Three stages with retiming reduced logic levels by 14% but did not move
Fmax. The bottleneck moved *inside* the arbiter rather than off it.

### What this means

Per our spec, the achievable bucket is now **< 150 MHz**, which says the
cone needs deeper architectural change and a third pipeline stage alone
is not enough. The remaining 36-level cone is the 8-way priority+slack
compare tree + 256-bit `sel_req` mux. The recommended next step is
Phase 2's **tournament-tree arbiter**:

- Replace the single-cycle 8-way compare with a pairwise tree
- Register the intermediate compare results (4-way at level 1,
  2-way at level 2, 1-way at level 3)
- Re-route the `rr_ptr` update on a separate, shorter path

Estimated post-route Fmax with that arbiter on xczu7ev: 200-300 MHz. Cost:
+2-3 cycles of arbitration latency (8 → 10-11 cycles end-to-end).

### Bitstream + Phase 1 final

The 3-stage build is what `results/impl/kvq_top_wrapper.bit` contains.
12/12 XSim regression passes. Timing closure at 400 MHz is **NOT met**;
the design ships as a Phase 1 deliverable that closes timing at the
documented Fmax of ~86 MHz and demonstrates the architectural claims at
that clock rate. Phase 2 (tournament-tree arbiter) is the gating work for
400 MHz claims.

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
