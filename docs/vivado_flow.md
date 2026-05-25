# CXL-KV Forge-QoS — Phase 1 Vivado Flow

This document covers the Phase 1 batch flow (synth + impl + bitstream) and the
GUI commands for inspecting the block design and post-route schematic.

## Headless build

```bash
bash scripts/run_vivado_synth.sh
```

The wrapper sources Vivado's `settings64.sh` via `$PATH`, then invokes two
Tcl steps:

1. `vivado/create_project.tcl` — creates the Vivado project at
   `build/vivado/kvq_phase1/`, adds the RTL (`rtl/*.sv` and
   `rtl/kvq_top_bd_wrap.v` — a Verilog shim Vivado IPI requires because
   it cannot reference a SystemVerilog module directly), and writes
   `constraints.xdc` to the constraints fileset.

2. `vivado/synth_impl_bitstream.tcl` — sources
   `vivado/create_block_design.tcl` to build the block design around
   `kvq_top_bd_wrap`, sets the BD wrapper as the synthesis top, then runs
   `synth_1` -> `impl_1` -> `write_bitstream`.

### Part selection

The default target is `xczu9eg-ffvb1156-2-e` (ZCU102). Override for WebPack:

```bash
VIVADO_PART=xczu3eg-sbva484-1-e bash scripts/run_vivado_synth.sh
```

The block design uses no parts of the chip that are ZCU102-exclusive, so any
Zynq UltraScale+ MPSoC supported by your Vivado install works. The PS
configuration uses defaults (no board preset) when the part is not
`xczu9eg*`.

### Block design contents

`create_block_design.tcl` produces `kvq_phase1_bd` containing:

| Block | Role |
|---|---|
| `ps_e_0` (zynq_ultra_ps_e) | ZCU102 PS, exposes M_AXI_HPM0_FPD and one S_AXI_HP*_FPD |
| `axi_dma_0` (axi_dma) | Drives the 256-bit AXIS request, sinks the response |
| `smartconnect_0` | PS HPM0 → axi_dma.S_AXI_LITE (and Phase 2: kvq AXI4-Lite) |
| `smartconnect_data` | DMA M_AXI MM2S/S2MM → PS S_AXI HP1 |
| `reset_0` (proc_sys_reset) | Synchronizes PS PL_RESETN0 to the PL clock domain |
| `kvq_top_0` (kvq_top_bd_wrap) | The Phase 1 RTL under test |
| `system_ila_0` (system_ila) | 12 probes on AXIS handshakes + arbiter + credit + per-tenant occupancy |
| `kvq_tieoff_*` (xlconstant) | Tie-offs on the kvq AXI4-Lite slave; PS programming of contracts lands in Phase 2 |

The standalone kvq_top has 489 top-level ports. All of them are absorbed
inside the BD; the BD wrapper's external boundary is only the PS DDR/MIO/JTAG
pins.

### Clock and reset

The Phase 1 BD uses **PS PL_CLK0 directly** as the design clock. PL_CLK0
defaults to ~96.97 MHz on the ZCU102 PS PLL — close to, but not exactly,
the 250 MHz target named in the spec. The 250 MHz target survives in
`vivado/constraints.xdc` for the standalone synth path and in the
standalone XSim testbench (`tb_kvq_top` drives a 4 ns clock period). The
clk_wiz multiplier to 250 MHz is a Phase 2 wiring task — the PS PLL's
discrete dividers make picking a clk_wiz PRIM_IN_FREQ that exactly matches
the PS output brittle across Vivado versions.

### ILA probes

`system_ila_0` exposes 12 probes:

| # | Width | Signal |
|---|---|---|
| 0 | 1  | `s_axis_req_tvalid` |
| 1 | 1  | `s_axis_req_tready` |
| 2 | 16 | request `tenant_id` (slice of AXIS tdata [231:216]) |
| 3 | 1  | `m_axis_resp_tvalid` |
| 4 | 1  | `m_axis_resp_tready` |
| 5 | 8  | response status byte (slice of AXIS tdata [255:248]) |
| 6 | 1  | `dbg_deadline_miss` |
| 7 | 3  | `dbg_arb_sel_tenant_idx` |
| 8 | 32 | `dbg_credit_snapshot` |
| 9 | 32 | `dbg_latency_cycles` |
| 10 | 1 | `dbg_credit_starvation_pulse` |
| 11 | 40 | `dbg_per_tenant_occupancy_flat` (5 bits × 8 tenants) |

ILA sample depth defaults to 4096. Trigger conditions are set in the
Vivado HW Manager GUI (no programmatic trigger in the BD Tcl).

## Artifacts

| Path | Contents |
|---|---|
| `results/synth/zcu102_synth_util.rpt` | Post-synthesis utilization |
| `results/synth/zcu102_timing_summary.rpt` | Post-synthesis timing summary |
| `results/synth/synth.log` | Full stdout/stderr for both Vivado invocations |
| `results/impl/zcu102_post_route_util.rpt` | Post-route utilization |
| `results/impl/zcu102_post_route_timing.rpt` | Post-route timing summary |
| `results/impl/kvq_top_wrapper.bit` | Programming bitstream |
| `results/impl/kvq_top_wrapper.ltx` | Debug probes file for Vivado HW Manager |

Timing closure is NOT asserted by the script. Inspect
`zcu102_post_route_timing.rpt` for the WNS/TNS numbers.

## Open the BD in Vivado GUI

```bash
vivado -nojournal -nolog \
       -source <(echo "open_project build/vivado/kvq_phase1/kvq_phase1.xpr; \
                       open_bd_design build/vivado/kvq_phase1/kvq_phase1.gen/sources_1/bd/kvq_phase1_bd/kvq_phase1_bd.bd; \
                       start_gui")
```

The IPI canvas appears with the full kvq_phase1_bd. The `kvq_top_0` block
is double-clickable to descend into the RTL.

## Open post-route schematic

After a successful build, the routed netlist is openable as:

```bash
vivado -nojournal -nolog \
       -source <(echo "open_project build/vivado/kvq_phase1/kvq_phase1.xpr; \
                       open_run impl_1; \
                       start_gui")
```

Then **Flow Navigator > IMPLEMENTATION > Open Implemented Design > Schematic**.

## Re-targeting ZCU102 from a WebPack run

If you ran the flow under `VIVADO_PART=xczu3eg-...` to get artifacts on a
WebPack-licensed part and now want to re-target the real ZCU102:

```bash
rm -rf build/vivado results/synth/* results/impl/*
unset VIVADO_PART          # back to xczu9eg-ffvb1156-2-e
bash scripts/run_vivado_synth.sh
```

The BD Tcl detects `xczu9eg*` and applies the ZCU102 board preset; on
smaller parts it falls back to the PS defaults.
