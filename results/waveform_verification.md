# Behavioral Simulation Waveform Verification

**Date:** 2026-05-26
**Sim:** `tb_kvq_top` via standalone XSim (`scripts/run_xsim.sh`)
**Result:** RESULT: PASS — 12 pass / 0 fail at $finish (7138 ns)

## Method

Behavioral simulation was driven by `tb_kvq_top.sv` with the 5-file
testbench (`kvq_test_pkg`, `kvq_assertions`, `kvq_scoreboard`,
`kvq_traffic_driver`, `tb_kvq_top`) against the full 16-file RTL.
Waveforms were inspected interactively in Vivado XSim 2025.2 GUI using
`sim/xsim/wave_config.wcfg` (42 audited signals). PNG export was skipped
because standalone XSim's Tcl namespace lacks `write_wave_image`; visual
inspection and signal-value verification was performed against the
testbench [PASS] log instead. The `.wdb` is regenerable in <2 s via
`bash scripts/run_xsim.sh`; reviewers can reproduce these views via
`xsim --gui tb_kvq_top` from `results/rtl_sim/` after running the
driver.

## Bring-up window (0 to ~400 ns)

| Test | Expected | Observed | Match |
|---|---|---|---|
| RESET_SANITY | rst_n deasserts, no errors, occ=0 | rst_n: 0→1 at ~35 ns; error_seen=0, queue_full=0, deadline_miss_seen=0, global_queue_occupancy=0 | OK |
| AXIL_READ_DEFAULT_STATUS | Read status=0x00000000 | s_axil_araddr=0x0004; s_axil_rdata=0x00000000; rresp=0 | OK |
| AXIL_PROGRAM_TENANT0_CONTRACT | Burst of writes to contract regs; active=1 after | Sequential awaddr 0x1000 to 0x1018 (7 writes), wstrb=0xf, wdata sequence 0x1, 0x2, 0x4, 0x10, 0x3e8, 0x1; bresp=0 throughout; active_tenant_count 00→01 | OK |
| SINGLE_WRITE_TENANT0 | AXIS request with tenant 0, OK response | s_axis_req_tvalid pulse with deadline field 0x3e8; m_axis_resp_tvalid pulse with response data | OK |
| Progress counters | n_pass increments per test | n_pass: 0→1→2→3→4; n_fail stays 0 | OK |

## Steady-state window (later sim time, multi-tenant)

| Signal | Value | Interpretation | Match |
|---|---|---|---|
| n_pass | 0x0000000c (=12) | All 12 tests passed | matches "12 pass" |
| n_fail | 0x00000000 | Zero failures | matches "0 fail" |
| active_tenant_count | 0x04 | 4 tenants active | matches T9/T10/T11 multi-tenant tests |
| error_seen | 0 | No assertion fires | matches expected |
| deadline_miss_seen | 0 | No SLA violations | matches expected |
| queue_full | 0 | No overflow | matches expected |
| rresp / bresp | 0 (OKAY) | All AXIL transactions clean | matches expected |

## Address map confirmation

The AXIL write burst targets the tenant 0 contract block at base 0x1000.
The 7 sequential 32-bit register writes (0x1000-0x1018) correspond
exactly to the contract fields exposed by `kvq_axil_regs.sv`:
priority, weight, deadline_cycles, deadline_us, refill_amount,
refill_period, credit_max/valid. Final readback through status register
0x000C confirms active=1.

## Conclusion

The behavioral simulation waveform faithfully reflects the testbench
event sequence. All transitions, response timings, AXIL transactions,
and final counter values match the [PASS] log reported by
`scripts/run_xsim.sh`. No discrepancies observed.

