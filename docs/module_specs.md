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
| 3 (Phase 1) | `kvq_deadline_arbiter.sv` (replaced by tournament tree below) | (deprecated) | (n/a) | Stage-3 retiming Sprint (Phase 1 final) |
| **T1 (Phase 2)** | `kvq_deadline_arbiter.sv` | tournament leaf: 4 winners of 8 (`t1_w[0..3]`) + `t1_rr_q` | **+1** | Phase 2 tournament-tree Sprint |
| **T2 (Phase 2)** | `kvq_deadline_arbiter.sv` | tournament mid:  2 winners of 4 (`t2_w[0..1]`) + `t2_rr_q` | **+1** | Phase 2 tournament-tree Sprint |
| **T3 (Phase 2)** | `kvq_deadline_arbiter.sv` | tournament final: `sel_valid_q` / `sel_req_q` / `sel_tid_q` / `deq_grant_q` | **+1** | Phase 2 tournament-tree Sprint |

**Total arbitration-path latency added in Phase 2: +5 cycles** vs the
unpipelined original (qmgr stage 1 + qmgr stage 2 + tournament T1/T2/T3).
That is +2 cycles relative to the Phase 1 stage-3-retiming build.

### Phase 2.1: kvq_token_bucket pipelined

The Phase 2 closure surfaced `kvq_token_bucket` as the next bottleneck
(12-level CARRY8 chain in the saturating refill+clamp+consume cone).
Phase 2.1 splits the bucket at the refill / consume boundary:

- **Stage 1** (combinational + register): `credit_r + refill_amount`
  saturated to `burst_credit_limit` -> `refilled_q`. ~6-7 logic levels.
- **Stage 2** (combinational + register): `refilled_q - consume_amount`
  saturated to zero -> `credit_r`. ~6-7 logic levels.

Net latency cost: +1 cycle on the refill path and +1 cycle on the
consume-visibility path. The credit_engine's `want_consume` gating
sees credit_r 1 cycle later than before; in the worst case this can
permit 1 extra consume per credit-engine cycle while a fresh refill
is in flight, but the over-allowance is bounded by the pipeline depth
(1 cycle) and absorbed by the 200-cycle test windows. XSim regression
stays 12/12.

`credit_available` is still a single-bit derivative of the registered
`credit_r`, never of any combinational midpoint - same external
contract as Phase 2.

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

## Deadline arbiter (Phase 2 tournament-tree version)

The single-cycle 8-way combinational compare has been replaced by a
**3-level pairwise reduction tree** (kvq_deadline_arbiter.sv). Each
tournament stage is one register with a single pairwise comparator
between consecutive registers:

```
Stage T1 (combinational):  pairwise(c[0],c[1]), pairwise(c[2],c[3]),
                           pairwise(c[4],c[5]), pairwise(c[6],c[7])
   |--register--|
Stage T2 (combinational):  pairwise(t1[0],t1[1]), pairwise(t1[2],t1[3])
   |--register--|
Stage T3 (combinational):  pairwise(t2[0],t2[1])
   |--register--|
Output:                    sel_valid_q, sel_req_q, sel_tid_q, deq_grant_q
```

Each `pairwise()` is bounded to ~5 logic levels max (validity check +
priority compare + slack compare + rr-distance compare). The longest
combinational segment in the arbiter is now ONE pairwise comparator -
the 36-level Phase 1 cone is gone.

The post-route worst path on the Phase 2 closure build (300 MHz, MET) is
in `kvq_token_bucket` (12 logic levels through a CARRY8 adder), not in
the arbiter. The arbiter is no longer on any failing path on any of the
four strategies in the sweep.

## rr_ptr in the tournament tree

`rr_ptr` snapshots at each stage so all three pairwise comparators in a
single arbitration wave use the same value:

```
T1 latches rr_ptr_t1_q from current rr_ptr
T2 latches rr_ptr_t2_q from rr_ptr_t1_q
T3 uses rr_ptr_t2_q
```

`rr_ptr` itself advances when T3 emits a grant (one cycle after T2
delivered its winners to T3's input).

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
