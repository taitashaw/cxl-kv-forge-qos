# CXL-KV Forge-QoS — Module specs and pipeline latency

This document tracks the per-module input-to-output cycle latencies, so that
testbench expectations and downstream consumers stay accurate as the
pipeline is retimed.

## Arbitration path latency

The arbitration path is the loop **qmgr → arbiter → mem_engine accept**.
Pipelining has been applied in three stages over the course of Phase 1.

| stage | location | what is registered | added cycles | introduced in |
|---|---|---|---|---|
| baseline | (none) | nothing - pure combinational | +0 | original Phase 1 RTL |
| 1 | `kvq_per_tenant_queue_manager.sv` | `deq_req_r` / `deq_valid_r` (q_mem readout) | +1 | 400 MHz retarget Sprint |
| 2 | `kvq_per_tenant_queue_manager.sv` | `deq_grant_r` (arbiter → qmgr feedback) | +1 | 400 MHz retarget Sprint |
| 3 | `kvq_deadline_arbiter.sv` | `sel_valid_q` / `sel_req_q` / `sel_tid_q` / `deq_grant_q` (with `retiming_backward = 1`) | +1 | Stage-3 retiming Sprint |

**Total arbitration-path latency added: +3 cycles** vs the unpipelined
Phase 1 baseline.

## End-to-end response latency

For a request that enqueues into an empty per-tenant queue and is granted
on the first arbitration cycle, the cycle counts from `s_axis_req_tvalid &&
tready` to `m_axis_resp_tvalid && tready` are approximately:

| build | cycles | notes |
|---|---|---|
| unpipelined baseline | ~5-6 | parser + arbiter combinational + mem_engine S_WAIT/S_ISSUE/S_LATCH/S_RESP |
| 2-stage pipelined | ~7-8 | +2 cycles from stage-1 and stage-2 in qmgr |
| **3-stage pipelined (current)** | **~8-9** | +1 cycle from stage-3 in arbiter |

Plus `cfg_mem_latency_cycles` for any extra S_WAIT cycles the memory
engine is configured to insert.

## XSim regression behavior under pipeline shifts

`tb_kvq_top.sv` checks **status fields and hit/deadline_miss flags**, not
exact cycle latencies. The 200-cycle `wait_for_resp` window absorbs every
pipelining shift documented above without requiring any test-vector
regeneration. All 12 directed tests pass on every stage configuration.

If a future Sprint adds a test that *does* assert a specific cycle count,
add the expected value to `tests/expected_outputs/<test>.csv` and update
this document with the new arbitration-path latency.

## What the deadline arbiter still does in one cycle

After stage 3, the arbiter's *internal* combinational cone is still:
- the 8-way priority+slack comparison tree to pick `best_idx`
- the 256-bit mux `deq_req[best_idx]` that feeds `sel_req_q`
- the rr_ptr update (combinational `rr_ptr_q1 = best_idx + 1`)

Vivado's retimer pulls the `sel_req_q` register backward into this cone
(see `_bret_*` suffixes in the post-route timing report), but it cannot
break the cone below ~36 logic levels without a structural RTL change.
That structural change - a registered tournament-tree compare - is
Phase 2 work.

## Module-by-module summary

### `kvq_request_parser`
- Combinational decode of the 256-bit AXIS packet
- 1-cycle latch on the parsed struct (`parsed_valid` / `parsed`)
- Latency: 1 cycle from AXIS handshake to `m_req_valid`

### `kvq_credit_engine`
- Single-cycle credit check + consume
- Latency: 0 cycles in the forward path (combinational gating)

### `kvq_per_tenant_queue_manager` (post 2-stage pipeline)
- Enqueue: 1-cycle FFs on `q_head`/`q_tail`/`q_count`
- Dequeue interface to arbiter: `deq_req_r` adds +1 cycle (stage 1)
- Grant feedback from arbiter: `deq_grant_r` adds +1 cycle (stage 2)

### `kvq_deadline_arbiter` (post stage-3 register)
- Combinational compare cone (36 logic levels after retiming)
- `sel_valid_q` / `sel_req_q` / `sel_tid_q` / `deq_grant_q` register at output
- Latency: 1 cycle from `deq_valid_r` becoming live to `sel_valid_q` asserting

### `kvq_memory_engine`
- 4 FSM states: S_IDLE → S_WAIT(n) → S_ISSUE → S_LATCH → S_RESP
- Latency: 4 + `cfg_mem_latency_cycles` cycles from accept to `out_valid`

### `kvq_response_builder`
- 1-cycle register slice (tdata_r / tvalid_r) drained on AXIS handshake
- Latency: 1 cycle from mem_engine `out_valid` to AXIS `tvalid`

Total typical path: parser(1) + credit(0) + qmgr_stage1(1) +
arb_stage3(1) + qmgr_stage2_grant(1) + mem(4+) + resp(1) = ~8-9 cycles
end-to-end at the BD's 400 MHz clk_wiz_0 output.
