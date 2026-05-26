# CXL-KV Forge-QoS — Phase 1 Simulation Flow

This document covers the headless and GUI XSim flows for the Phase 1 testbench.

## Headless regression

```bash
bash scripts/run_xsim.sh
```

The wrapper sources Vivado/XSim, then runs:

1. `xvlog -sv ...` over `rtl/*.sv` and `sim/tb/*.sv`
2. `xelab -debug typical -L work tb_kvq_top -snapshot tb_kvq_top`
3. `xsim tb_kvq_top --runall --tclbatch sim/xsim/run_xsim.tcl --wdb tb_kvq_top.wdb`

It exits 0 on `RESULT: PASS` and 1 on `RESULT: FAIL`. All artifacts land in `results/rtl_sim/`:

| File | Purpose |
|---|---|
| `tb_kvq_top.wdb` | Full waveform database (this is the file the GUI opens) |
| `xsim.log` | Run-time stdout/stderr including pass/fail banner |
| `xsim_compile.log` / `xsim_elab.log` | xvlog/xelab transcripts |
| `phase1_xsim_summary.csv` | Per-test result row, written by the testbench itself |

## Open the wave database in standalone XSim GUI

Pre-loaded with the curated signal groups from `sim/xsim/wave_config.wcfg`:

```bash
cd results/rtl_sim
cp ../../sim/xsim/wave_config.wcfg .          # the .wcfg uses a relative ref to tb_kvq_top.wdb
xsim --gui tb_kvq_top.wdb --view wave_config.wcfg
```

Tested on Vivado 2025.2. The `--view` flag requires the `--gui` flag and the
`.wcfg` to sit beside the `.wdb` because of the relative `db_ref path` inside
the wave config.

The groups that appear pre-expanded in the Wave window:

| Group | Signals |
|---|---|
| `clk_reset` | `clk`, `rst_n` |
| `axis_request` | `s_axis_req_tvalid/tready/tlast`, parsed `opcode`, `request_id`, `tenant_id`, `prio`, `deadline_cycles` |
| `axis_response` | `m_axis_resp_tvalid/tready/tlast`, packed response `status`/`request_id`/`tenant_id`/`latency_cycles`/`deadline_miss`/`hit` |
| `arbiter_credits` | arbiter `sel_valid/sel_ready/sel_tenant_idx/best_idx/best_prio/best_slack/rr_ptr` plus `credit_engine.credit_snapshot/credit_starvation_pulse/refill_pulse` |
| `per_tenant_queues` | `qmgr.global_queue_occupancy`, `queue_full`, `per_tenant_occupancy[0..7]` |
| `axi4_lite` | full AXI4-Lite handshake (`aw*/w*/b*/ar*/r*`) and `wdata`/`rdata` |
| `top_status` | `error_seen`, `queue_full`, `deadline_miss_seen`, `active_tenant_count`, `global_queue_occupancy` |

## Open the wave database from Vivado GUI

If you prefer the Vivado launcher (same XSim engine, fuller IDE):

```bash
vivado -nojournal -nolog -mode gui \
       -source <(echo "open_wave_database results/rtl_sim/tb_kvq_top.wdb; \
                       open_wave_config sim/xsim/wave_config.wcfg")
```

Equivalent manual path: launch Vivado GUI, then
**Tools > Open Waveform Database** -> `results/rtl_sim/tb_kvq_top.wdb`, then
**File > Open Waveform Configuration** -> `sim/xsim/wave_config.wcfg`.

## Targeting a specific test

`sim/tb/tb_kvq_top.sv` runs all 12 directed tests sequentially. To focus on a
single test in the GUI, set a breakpoint on the `current_test` assignment for
the test you care about, or use `Run > Run for Specified Time` to advance to
the relevant region. The waveform spans the full 7 microseconds of simulated
time so all 12 tests are visible.

## Re-running after editing the wave layout

If you re-arrange signals in the GUI, **File > Save Waveform Configuration As**
back to `sim/xsim/wave_config.wcfg` so the layout persists into the next
headless+GUI round trip.

## Focused key-signals view

`sim/xsim/key_signals.tcl` is a smaller, narrative-focused wave layout that
shows only the signals demonstrating the Phase 1 architectural claims (AXIS
handshake, AXI4-Lite contract programming, arbiter pulses + winner slack /
priority, credits, queue occupancy, SLA counters, TB pass/fail). Use it when
you want to read the wave like a story rather than dump everything.

### Two ways to use it

**From an already-open xsim GUI session** (after launching xsim --gui and
opening the .wdb):

```tcl
source sim/xsim/key_signals.tcl
```

**At launch** (parses cleanly even without DISPLAY — useful for CI):

```bash
cd results/rtl_sim
xsim tb_kvq_top --gui --tclbatch ../../sim/xsim/key_signals.tcl
```

### What to look for

- **arb_sel_tenant_idx** must change between distinct values during the
  multi-tenant tests (TWO_TENANT_PRIORITY_ORDER, EARLIEST_DEADLINE_FIRST_BASIC,
  CREDIT_EXHAUSTION_OR_STALL). If it stays pinned to one tenant, arbitration
  is broken.
- **best_slack** must be the minimum among the eligible tenants on every
  cycle that **arb_sel_valid** pulses. The eligible set is the bits set in
  **qm_deq_valid**. Mismatch ⇒ arbiter is picking the wrong winner.
- **per_tenant_occ[0..7]** must not all sit at zero throughout the run.
  At least the active tenants during T4..T11 should accumulate some
  occupancy. All-zero everywhere typically means the credit engine is
  rejecting all enqueues.

### `run all` warning

`tb_kvq_top.sv:413` calls `$finish` at ~7038 ns. Do **NOT** run a second
`run all` after that — XSim happily keeps toggling clocks into the
post-finish region, but the testbench has already exited so counters and
status flags appear flat afterward. If you need to look further into time
you have to re-elaborate; you cannot extend the run past `$finish`.
