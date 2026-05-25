# xczu7ev-ffvc1156-2-e build results

Build date: 2026-05-25
Vivado: 2025.2 (build 6299465)
Source RTL: 2-stage pipelined queue manager (kvq_per_tenant_queue_manager.sv
register-A on `deq_req`/`deq_valid` and register-B on `deq_grant`)
Target frequency: 400 MHz (2.500 ns period, clk_wiz_0 out)

## Headline

| metric | value |
|---|---|
| Target clock | 400 MHz (2.500 ns) |
| Post-route WNS | **-9.135 ns** |
| Post-route TNS | **-36,857.996 ns** |
| Setup failing endpoints | 19,843 / 68,314 |
| Hold failing endpoints  | 0 |
| Logic levels on critical path | 42 |
| Critical path data delay | 11.605 ns (logic 3.779 / route 7.826) |
| **Achieved Fmax** | **1 / 11.605 ns = 86.2 MHz** |
| Bitstream | results/impl/kvq_top_wrapper.bit (19.3 MB) |

## Comparison vs xczu3eg-sbva484-1-e

| metric | xczu3eg (small) | xczu7ev (3.3x larger) | delta |
|---|---|---|---|
| WNS at 400 MHz | -9.996 ns | -9.135 ns | +0.86 ns |
| TNS | -47,237 ns | -36,858 ns | -22% |
| Failing endpoints | 21,520 | 19,843 | -8% |
| Logic delay (worst) | 4.246 ns | 3.779 ns | -11% |
| Route delay (worst) | 8.207 ns | 7.826 ns | -5% |
| Logic levels | 45 | 42 | -7% |
| **Fmax** | **80.0 MHz** | **86.2 MHz** | **+7.5%** |

## Critical path

- **Source:** `kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/u_arb/rr_ptr_reg[0]/C`
- **Destination:** `kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/u_mem/held_req_reg[request_id][2]/D`
- **Path group:** `clk_out1_kvq_phase1_bd_clk_wiz_0_0`
- **Logic levels: 42** (CARRY8=8, LUT2=1, LUT3=1, LUT4=1, LUT5=11, LUT6=20)

The path is the combinational arbiter winner-selection cone:
`rr_ptr → best_idx mux → sel_req mux on deq_req[best_idx] → mem_engine.held_req.D`.

The 2-stage qmgr pipeline (`deq_req_r`, `deq_grant_r`) successfully broke the
previous worst path (`q_head → q_head` inside the qmgr loop) — that path is
now passing at +0.003 ns slack. The new bottleneck is the arbiter→mem path
which the qmgr pipelining did not touch.

## Utilization

| resource | used | available | util% |
|---|---|---|---|
| CLB LUTs | 18,719 | 230,400 | 8.12% |
| CLB Registers | 28,131 | 460,800 | 6.10% |
| Block RAM Tile | 8 | 312 | 2.56% |

The chip is significantly under-used. The remaining timing failure is RTL
logic depth, not part capacity.

## Verdict

xczu7ev does NOT meaningfully improve Fmax over xczu3eg with the existing
2-stage pipelined RTL. The 7.5% improvement (80 → 86 MHz) falls well short
of the user-specified ≥200 MHz threshold for "meaningful". The dominant
factor is logic depth in the combinational arbiter→mem_engine cone (42
levels of LUT/CARRY), not part-level routing distance.

Per the user's instruction in Sprint X follow-up ("If it does not improve
meaningfully, document why and revert to the xczu3eg result"), the default
part has been reverted to xczu3eg-sbva484-1-e. xczu7ev remains accessible
via `VIVADO_PART=xczu7ev-ffvc1156-2-e bash scripts/run_vivado_synth.sh`.

## How to reach the 400/333 MHz targets

The 86 MHz ceiling is set by combinational logic depth in the arbiter, not
the part. Three options exist (all require either RTL changes or part
family change):

1. **Add a third pipeline stage** (register `sel_valid` / `sel_req` /
   `sel_tenant_idx` in the arbiter). Breaks the 42-level cone into two
   shorter cones. Estimated Fmax: ~200-250 MHz. Cost: +1 cycle arbitration
   latency. Forbidden by the current Sprint instruction.

2. **Re-architect the arbiter** to use a tournament tree with intermediate
   registers, removing the 8-way single-cycle compare. Estimated Fmax:
   ~333-400 MHz. Cost: 2-3 cycles arbitration latency.

3. **Migrate to Agilex 7 -3 speed grade.** Logic delay at -3 speed grade
   is ~40% faster than UltraScale+ -2. Same RTL would reach ~140 MHz on
   the same logic depth without RTL changes - still below 400 MHz but
   meaningful improvement, and Agilex has the headroom for the additional
   pipelining to reach 400 MHz cleanly.

Phase 1 stays at xczu3eg / 80 MHz Fmax. The 400 MHz constraint remains in
the BD (clk_wiz_0 still targets 400 MHz) so future Sprint Y or RTL revisions
get measured against the same goal.
