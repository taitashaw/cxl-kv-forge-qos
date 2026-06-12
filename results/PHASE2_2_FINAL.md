# Phase 2.2 — 400 MHz re-closure signoff

Closed-timing signoff for CXL-KV Forge-QoS at the 400 MHz stretch target on
xczu7ev. Builds on the Phase 2.1 350 MHz signoff (`PHASE2_1_FINAL.md`); the
delta is one registered crossing, one arbiter correctness fix, and a
strengthened regression.

## Headline

| metric | value |
|---|---|
| Date | 2026-06-12 |
| Part | xczu7ev-ffvc1156-2-e |
| Design clock | **400 MHz** (clk_wiz_0 output, 2.500 ns period, measured 400.019 MHz) |
| Post-route WNS (setup, design clock group) | **+0.033 ns (MET)** |
| Post-route WNS (design-level, incl. recovery) | **+0.026 ns (MET)** |
| Post-route TNS (setup) | **0.000 ns** |
| Setup failing endpoints | **0 / 77,540** |
| Hold WNS / failing | +0.010 ns / 0 |
| Pulse width (fabric) | clean |
| Pulse width (PS port clocks) | 4 violations, −0.500 ns (pre-existing, see below) |
| Winning impl strategy | **Performance_Explore** (3 of 4 strategies met: +0.033 / +0.025 / +0.002) |
| Synth retiming | enabled (`STEPS.SYNTH_DESIGN.ARGS.RETIMING true`) |
| XSim regression | **13 / 13 PASS** (12 inherited + backpressure injection), SVA clean |
| Per-stream throughput | 256 b × 400 MHz / 1000 = **102.4 Gb/s** |
| Aggregate AXIS throughput | request + response = **204.8 Gb/s** |
| Arbitration-path latency | ~11–12 cycles ≈ **27.5 to 30.0 ns** (+1 cycle vs Phase 2.1, from the register slice) |
| Bitstream | `results/impl/kvq_top_wrapper.bit` (19.3 MB, debug-free measurement build) |
| Debug probes | none in this build — the Phase 2.1 `kvq_top_wrapper.ltx` is retired with it (stale against this bitstream); `closure_inmem.tcl` regenerates probes for debug builds |
| Build wall clock | ~25 min (create → synth → 4 parallel impl strategies → bitstream, 24-thread host) |

## What changed since Phase 2.1

### 1. Registered enqueue crossing (`rtl/kvq_top.sv`) — the timing fix

The Phase 2.1 RTL at a 400 MHz target failed with WNS **−0.192 ns**
(TNS −834.045, 9,123 failing endpoints; best of four strategies,
Performance_ExtraTimingOpt). The worst path ran
`u_credit/.../credit_r_reg[0] → u_qmgr/q_mem_reg[0][10][kv_address][4]/CE`:
2.499 ns data path = **0.703 ns logic (28%) + 1.796 ns routing (72%)** across
8 logic levels — a routing-dominated cross-module net, not logic depth. That
pre-fix report is preserved verbatim at
`results/impl/baseline_400mhz_prefix/post_route_timing.rpt`.

The fix is a forward register slice on the credit→queue-manager beat
(`{valid, req, max_depth}` captured and held until accepted; ready passed
through; flushed by soft_reset). +1 cycle of enqueue latency, tolerated by
the QoS arbitration budget. After the fix, the worst path on the design clock
is the slice's own output net into the queue memory: 2.168 ns at **zero**
logic levels, 96.3% routing — the cross-module wire now owns a full period.

### 2. Wave-admission interlock (`rtl/kvq_deadline_arbiter.sv`) — a correctness fix

Strengthening verification for the slice exposed a latent Phase 2 bug: the
pipelined tournament tree re-samples un-popped queue heads into a new wave
every cycle, while the pop lands at T3 plus the queue manager's
`deq_grant_r`/stage-A readout lag. One head can ride several overlapping
waves; each stale grant pops a successor entry while presenting the old
request's data. Measured in XSim before the fix: **2 queued beats → 4 grants,
the head request issued 4×, the successor never issued.** The inherited tests
could not see this (they spot-check one request id per batch; pops on empty
queues are guarded, so single-request tests only produced duplicate
responses).

The interlock admits a new wave only when the tree is empty and the head
readout has refreshed (3 cycles) after the last grant. The tree's pipelined
structure — the reason Phase 2 closes timing — is untouched. Aggregate grant
rate becomes ~1 per 6 cycles, fully absorbed by the single-issue memory
engine. After the fix the same counters read 2 grants / each request issued
exactly once, and the suite-wide observed-response count drops 52 → 33 (the
difference was silent duplicates).

### 3. Strengthened regression (`sim/tb/`)

- `ENQ_CROSSING_BACKPRESSURE_INJECT` (test 13): forces a synthetic stall
  window on the credit→qmgr crossing (the queue manager's `enq_ready` is
  structurally constant-high, so a stalling consumer is emulated by forcing
  the interface idle from both sides), and demands exact-once completion:
  beat captured, held unmutated, upstream backpressured, 2 grants, each
  request issued exactly once.
- New SVA `a_enq_slice_stable` in `kvq_assertions.sv`: a beat presented to
  the queue manager holds, unmutated, until accepted.

### 4. Flow corrections (`vivado/`)

- `create_block_design.tcl`: clk_wiz `PRIM_SOURCE No_buffer` — with the
  default pin-source config, Vivado 2025.2 emits an input IBUF that
  opt_design removes as undriven, which disconnects the MMCM input and
  silently drops the generated fabric clock; the datapath then times
  unconstrained (one build was discarded after reading WNS +15.6 ns against a
  2.5 ns budget — an impossible number caught by checking the clock table).
  CLKOUT1 target set to 400 MHz.
- `create_project.tcl`: `constraints.xdc` (100% debug-core insertion, no
  clocks or IO) is disabled for timing-measurement builds, matching the
  conditions of the committed baselines. Debug builds use
  `closure_inmem.tcl`.

## Known limitation carried in this signoff

The PS AXI port clocks (`PS8/MAXIGP*ACLK`) are spec-limited to 333.33 MHz;
driving them at the 400 MHz fabric clock produces 4 min-period violations at
−0.500 ns. These are pre-existing (identical in the pre-fix baseline at this
target), sit outside the PL fabric, and would be resolved in deployment by
bridging the PS-facing AXI onto a ≤333 MHz clock domain. All other
limitations in `docs/phase1_known_limitations.md` stand.

## Reproduction

```bash
bash scripts/run_xsim.sh                                        # 13/13 + SVA
VIVADO_PART=xczu7ev-ffvc1156-2-e bash scripts/run_vivado_synth.sh  # 400 MHz sweep
```

Artifacts: `results/impl/phase2_strategy_sweep.md` (post-fix sweep),
`results/impl/strategy_Performance_Explore/post_route_timing.rpt` (winner),
`results/impl/baseline_400mhz_prefix/` (pre-fix 400 MHz baseline),
`results/rtl_sim/xsim.log` (13/13).
