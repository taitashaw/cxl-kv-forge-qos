# CXL-KV Forge-QoS - Phase 1 Verification Plan

## Goals

Prove that the Phase 1 RTL scaffold is real: every major submodule has a path that is exercised, every AXI handshake is observable, the contract programming surface is reachable from AXI4-Lite, and the QoS thesis (priority + deadline + isolation) is visible in directed scenarios.

Phase 1 does not attempt full coverage. The 45-test matrix from the spec is descoped to 12 directed tests; the remainder land in Phase 2.

## XSim directed tests

| # | Test                                | Purpose                                                                 |
|---|-------------------------------------|-------------------------------------------------------------------------|
| 1 | RESET_SANITY                        | After reset, all status flags are clear and queue occupancy is zero.   |
| 2 | AXIL_READ_DEFAULT_STATUS            | AXI4-Lite read of 0x004 returns 0 post-reset.                          |
| 3 | AXIL_PROGRAM_TENANT0_CONTRACT       | Contract write succeeds and `active_tenant_count` increments.          |
| 4 | SINGLE_WRITE_TENANT0                | Single AXIS WRITE returns OK; valid-bit set in BRAM.                   |
| 5 | SINGLE_READ_HIT_TENANT0             | READ to a previously-written address returns OK with hit=1.            |
| 6 | SINGLE_READ_MISS_TENANT0            | READ to an unwritten address returns MISS.                             |
| 7 | BAD_OPCODE_ERROR                    | Unknown opcode produces `KVQ_STATUS_ERR_BAD_OPCODE`.                   |
| 8 | CREDIT_EXHAUSTION_OR_STALL          | Small bucket plus burst input either yields error responses or visible input backpressure. |
| 9 | TWO_TENANT_PRIORITY_ORDER           | Low-prio queued first, high-prio queued second; both drain.            |
| 10| EARLIEST_DEADLINE_FIRST_BASIC       | Tighter deadline wins over looser deadline at equal priority class.    |
| 11| OUTPUT_BACKPRESSURE_HOLDS_RESPONSE  | With sink stalled, `m_axis_resp_tvalid` remains high and `tdata` stable. |
| 12| COUNTER_RESET                       | Writing 0x000 bit[2] resets TOTAL_REQUESTS to zero.                    |

Each test calls `record(test_name, ok, note)` and writes one line into `results/rtl_sim/phase1_xsim_summary.csv`. The summary banner reports total `pass/fail`. The simulation prints `RESULT: PASS` or `RESULT: FAIL` and the shell wrapper greps for that line to set its exit code.

## Assertions

`sim/tb/kvq_assertions.sv` checks:

- `s_axis_req_tdata` is stable while `tvalid && !tready`.
- `m_axis_resp_tdata` is stable while `tvalid && !tready`.
- The response status byte is never X after reset on a successful handshake.
- AXI4-Lite `bvalid` follows `awvalid` within 64 cycles.
- AXI4-Lite `rvalid` follows `arvalid` within 64 cycles.

Assertions are simulation-only; they are not compiled into `rtl/` and do not affect synthesis.

## Scoreboard behavior

`kvq_scoreboard.sv` snoops the AXIS response stream and records each response keyed by `request_id` into an associative array. Tests query `seen(rid)` to wait for completion and `get(rid)` to inspect status, hit, deadline_miss, latency, and credit/occupancy snapshots.

## Trace replay bridge

`scripts/trace_csv_to_sv_mem.py` converts Phase 0 CSV traces into 256-bit hex packets in the kvq_pkg layout. Three seed traces ship: `phase1_basic_trace.csv` (basic R/W mix), `phase1_qos_trace.csv` (priority interleave), `phase1_deadline_trace.csv` (deadline pressure). A Phase 2 testbench will optionally `$readmemh` these files instead of constructing requests inline.

## Pass / fail criteria

Phase 1 passes when:

- `bash scripts/run_xsim.sh` exits 0.
- `RESULT: PASS` is present in `results/rtl_sim/xsim.log`.
- No assertion failures are reported in `xsim.log`.

Phase 1 fails when any of the above are not satisfied. The wrapper script does not retry; it surfaces the failure for human review.

## Future tests (Phase 2 backlog)

- Multi-tenant fairness over long burst windows.
- Long-tail latency histograms exported from RTL (currently Python-side).
- Full 45-test directed matrix from the original spec.
- Random/constrained-random regression with coverage closure.
- Formal property checks on the credit engine (no underflow, no overflow).
