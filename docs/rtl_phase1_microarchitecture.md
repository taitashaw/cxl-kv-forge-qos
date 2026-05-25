# CXL-KV Forge-QoS - Phase 1 RTL Microarchitecture

## Phase 1 scope

Phase 1 delivers a structurally synthesizable SystemVerilog scaffold that mirrors the Phase 0 Python behavioral model. It is the first hardware baseline: AXI4-Stream front door, AXI4-Lite control plane, tenant contracts, token-bucket credits, per-tenant queues, deadline-aware arbitration, a BRAM-backed mock KV memory, response packing, counters, and an XSim testbench. Phase 1 is not a production CXL endpoint.

## What is implemented

- 256-bit AXI4-Stream request input (`s_axis_req_*`).
- 256-bit AXI4-Stream response output (`m_axis_resp_*`).
- Simplified AXI4-Lite control/status/contract programming (`s_axil_*`).
- Tenant contract table with `MAX_TENANTS = 8` entries and a permissive default fallback for unprogrammed entries.
- Per-tenant token-bucket credit enforcement with periodic refill.
- Per-tenant queues (`TENANT_QUEUE_DEPTH = 16` each, register-array storage).
- Deadline-aware arbiter (priority class, then deadline slack, then round-robin tie-break).
- Free-running 32-bit cycle counter feeding the latency tracker.
- Single-issue memory engine over a synchronous BRAM with a parallel valid-bit table for hit/miss.
- Response builder with mem-path priority over the error side-channel.
- Global SLA counters: total/read/write/prefetch requests, deadline-miss count, credit starvation, malformed requests, input/output backpressure cycles, max latency, cumulative latency, max queue occupancy.
- AXI4-Lite register map (0x000..0x03C globals, 0x1000-window contract programming).

## What is intentionally simplified (MVP)

- Service-unit cost table is fixed in `kvq_pkg::kvq_service_units`. No per-tenant cost scaling.
- Memory engine is single-issue. No outstanding-request tracking table; the latency tracker pairs the in-flight request with a single 32-bit issue tag.
- BRAM model is single-port, address-of-data placeholder (write data is the address itself). Real KV payload routing arrives in Phase 2.
- `PREFETCH`, `EVICT`, `INVALIDATE`, `QUERY_STATS`, `RESET_STATS`, `PROGRAM_CONTRACT`, `RESET_CONTRACT` packets return `OK` with appropriate flags but perform no behavior beyond counters. Real contract programming happens through AXI4-Lite.
- Token-bucket refill uses a single timer across tenants and snapshots the active tenant's contract per cycle. A per-tenant refill table is a Phase 2 task.
- Arbiter computes "deadline slack" from `req.deadline_cycles` directly because per-request enqueue timestamps are not persisted in queue memory; this matches the spec for Phase 1 MVP behavior.
- AXI4-Lite shim ignores `wstrb` and always returns `OKAY` (`bresp = rresp = 2'b00`).
- Percentile / histogram latency views remain Python-side. The hardware exposes max/cumulative latency only.
- Tenant contract readback over AXI4-Lite returns zero in MVP - programming is write-only from the host side.

## Datapath

```
AXIS req
  -> kvq_request_parser  (decode + bad_opcode/bad_framing)
  -> kvq_tenant_contract_table (combinational lookup, default fallback)
  -> kvq_credit_engine    (good-path or err side-channel)
  -> kvq_per_tenant_queue_manager
  -> kvq_deadline_arbiter (priority / slack / round-robin)
  -> kvq_latency_tracker  (issue tag = cycle counter)
  -> kvq_memory_engine    -> kvq_bram_model
  -> kvq_response_builder -> AXIS resp
```

Error and queue-full paths feed `kvq_error_handler`, which serializes them into the response builder's error input.

## Control path

`kvq_axil_regs` decodes write addresses 0x000..0x03C as globals and addresses with `addr[15:12] == 4'h1` as the contract programming window. Tenant index = `addr[8:6]`, field selector = `addr[5:2]`. Writes to 0x000 with bit[1] generate a single-cycle soft-reset pulse; bit[2] generates a counter-reset pulse. Reads route through a counter mux driven by `kvq_perf_counters.rb_sel`.

## Module hierarchy

```
kvq_top
├── kvq_request_parser
├── kvq_tenant_contract_table
├── kvq_credit_engine
│   └── kvq_token_bucket  x MAX_TENANTS (generate)
├── kvq_per_tenant_queue_manager
├── kvq_deadline_arbiter
├── kvq_latency_tracker
├── kvq_memory_engine
│   └── kvq_bram_model
├── kvq_response_builder
├── kvq_error_handler
├── kvq_sla_monitor
├── kvq_perf_counters
└── kvq_axil_regs
```

## Valid / ready strategy

All inter-module handshakes are AXI-style valid/ready: producer asserts `valid` and holds data stable until the consumer asserts `ready` on the same cycle. The parser, credit engine, queue manager, and arbiter never stall a downstream consumer with a partial transfer; the response builder holds `tvalid` asserted with stable `tdata` until `tready` is sampled high.

## Credit strategy

Each tenant's bucket has depth `contract.burst_credit_limit`. Every `REFILL_PERIOD_CYCLES` (default 64) cycles, the bucket refills `contract.min_bandwidth` credits, saturated to the burst limit. A request consumes `kvq_service_units(opcode)` credits on the cycle it transits from credit engine into the queue. If the bucket is short, the request is diverted to the error side-channel with `KVQ_STATUS_ERR_NO_CREDIT` and `credit_starvation_count` increments.

## Arbitration strategy

The arbiter is combinational. Each cycle it scans tenants starting at `rr_ptr` and picks the candidate with the lowest priority class, breaking ties by smaller deadline slack, and further ties by round-robin order. On grant, `rr_ptr` advances past the granted tenant. When the memory engine is busy (`in_ready` low), the arbiter does not pulse `deq_grant`, so the queue manager retains the head.

## Memory model

`kvq_bram_model` is one read/write port, registered output, `BRAM_DEPTH = 4096` entries, `DATA_WIDTH = 64`. A parallel `valid_bit[]` array tracks which addresses have been written. The memory engine asserts `we` on `KVQ_OP_WRITE`, `re` on `KVQ_OP_READ`. Soft reset clears the valid-bit array but not the data array (data without a valid bit is unreachable).

## Known limitations

See `phase1_known_limitations.md`.
