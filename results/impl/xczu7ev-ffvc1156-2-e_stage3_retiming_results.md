# xczu7ev-ffvc1156-2-e + 3-stage pipeline + retiming - build results

Build date: 2026-05-25
Vivado: 2025.2 (build 6299465)
Source RTL: 3-stage pipelined arbitration path
  - stage 1: qmgr `deq_req_r` / `deq_valid_r` register (kvq_per_tenant_queue_manager.sv)
  - stage 2: qmgr `deq_grant_r` register
  - stage 3: arbiter `sel_valid_q` / `sel_req_q` / `sel_tid_q` / `deq_grant_q`
             with `(* retiming_backward = 1 *)` (kvq_deadline_arbiter.sv)
Target frequency: 400 MHz (2.500 ns clk_wiz_0 out)
Synth retiming: enabled (`STEPS.SYNTH_DESIGN.ARGS.RETIMING true`)
phys_opt:       enabled with directive `AggressiveExplore`

## Headline

| metric | value |
|---|---|
| Target clock | 400 MHz (2.500 ns) |
| Post-route WNS | **-9.177 ns** |
| Post-route TNS | **-35,442.617 ns** |
| Setup failing endpoints | 21,085 / 69,626 |
| Hold failing endpoints  | 0 |
| Logic levels on critical path | 36 |
| Critical path data delay | 11.586 ns (logic 3.606 / route 7.980) |
| **Achieved Fmax** | **1 / 11.677 ns = 85.6 MHz** |
| Bitstream | results/impl/kvq_top_wrapper.bit (19.3 MB) |

## Critical path - did the bottleneck move off the arbiter cone?

**No.** It moved *deeper into* the arbiter cone, not off it.

| | 2-stage (previous run) | 3-stage + retiming (this run) |
|---|---|---|
| Source | `u_arb/rr_ptr_reg[0]` | `u_arb/sel_req_q_reg[opcode][7]_bret_6_rep` |
| Destination | `u_mem/held_req_reg[request_id][2]` | `u_arb/rr_ptr_reg[1]_rep` |
| Module crossing | u_arb → u_mem | both ends inside u_arb |
| Logic levels | 42 | 36 |
| Logic delay | 3.779 ns | 3.606 ns |
| Route delay | 7.826 ns | 7.980 ns |
| **Total** | **11.605 ns** | **11.586 ns** |

The `_bret_` and `_rep` suffixes show Vivado retiming was active: the stage-3
register I added at the arbiter output got pulled backward into the cone
and replicated for fanout. Logic depth dropped 42→36 (15%), but the
combinational mass between the moved-back register and `rr_ptr_reg` is still
36 levels deep and 7.98 ns of pure routing, which is the dominant term.

Side-by-side, the total path delay only improved by **0.019 ns**. The stage-3
register isolated the arbiter from u_mem (good — they don't share a critical
path anymore) but did not break the internal cone enough to close 400 MHz.

## Side-by-side with the previous xczu7ev 2-stage build

| metric | 2-stage (no retiming) | 3-stage + retiming | delta |
|---|---|---|---|
| WNS | -9.135 ns | -9.177 ns | -0.042 ns |
| TNS | -36,857.996 ns | -35,442.617 ns | -3.8% |
| Setup failing endpoints | 19,843 | 21,085 | +6.3% |
| Logic levels (worst) | 42 | 36 | -14.3% |
| Logic delay (worst) | 3.779 ns | 3.606 ns | -4.6% |
| Route delay (worst) | 7.826 ns | 7.980 ns | +2.0% |
| **Total path delay** | **11.605 ns** | **11.586 ns** | **-0.02 ns** |
| **Fmax** | **86.2 MHz** | **85.6 MHz** | **-0.7%** |
| LUTs used | 18,719 | 18,640 | -0.4% |
| FFs used | 28,131 | 28,808 | +2.4% (retiming added 677) |

Endpoint count went up by 6% because retiming inserted register replicas
(`_rep` suffix everywhere in the timing report), each contributing its own
setup endpoint. The +677 FF count is direct evidence that retiming pulled
the inserted register backward into the cone. The +2% route delta is the
extra distance those new replicas added.

## Did retiming take effect?

**Yes, but it didn't help Fmax.**

Evidence:
- Synth log has 2,957 lines mentioning `retim` or `_bret_`
- The critical-path source register name (`sel_req_q_reg[opcode][7]_bret_6_rep`)
  contains the Vivado `_bret_` suffix, which only appears on registers that
  Vivado's retimer pulled backward through combinational logic
- FF utilization grew by 677 cells (single-pass synth alone, no
  architectural FF additions in the RTL would have added that many)
- Logic levels dropped 42 → 36

The retimer did its job. The reason Fmax did not improve is that the new
limiting factor is the **routing delay** (~8 ns) between the placed
mid-cone register replicas and `rr_ptr_reg`, not logic depth. On a chip
with 8% utilization, you'd expect placement to keep these tight - but the
placer is treating the arbiter as a single dense cell cluster and the
routes between subcomponents inside it span tens of nanoseconds of net
delay.

## Verdict against the spec thresholds

| user threshold | our Fmax | decision |
|---|---|---|
| ≥ 200 MHz | 85.6 MHz | lock |
| 150-200 MHz | n/a | document + Phase 2 tournament-tree |
| **< 150 MHz** | **85.6 MHz** | **cone needs deeper architectural change** |

We fall into the third bucket. The third stage alone is not enough; the
arbiter's combinational priority+slack comparison tree, plus the 256-bit
`sel_req` mux on `deq_req[best_idx]`, plus the rr_ptr update — collectively
36 logic levels even after retiming — is the architectural bottleneck.

## What to do next (NOT done in this Sprint)

The user's contingency for the `< 150 MHz` case was a **tournament-tree
arbiter**: replace the current single-cycle 8-way priority+slack compare
with a pairwise tree, register the intermediate compare results, and
re-route the rr_ptr update separately. Estimated post-route Fmax with that
arbiter on xczu7ev: 200-300 MHz. Cost: +2-3 cycles of arbitration latency
(7→9 cycles total through the deadline-arb path) and a real RTL rewrite of
`kvq_deadline_arbiter.sv`. That work is Phase 2.

## XSim regression

12/12 PASS with the 3-stage RTL. Response latency shifted by +1 cycle from
the 2-stage build (now +3 cycles total beyond the unpipelined baseline).
No expected-output CSV regeneration was needed because tb_kvq_top.sv
checks status/hit/deadline_miss fields, not exact latency counts, and the
200-cycle `wait_for_resp` window absorbs the shift comfortably.
