# CXL-KV Forge-QoS

Hardware-Enforced SLA Controller for Multi-Tenant LLM KV-Cache Access.

Software LLM schedulers operate at millisecond to tens-of-milliseconds granularity, while KV-cache memory contention occurs at sub-microsecond granularity through queue head-of-line blocking, memory-bank contention, cache-line eviction, and burst interference. CXL-KV Forge-QoS closes this timescale gap by enforcing tenant credits, token-bucket bandwidth limits, queue isolation, deadline-aware arbitration, and SLA telemetry at AXI/CXL clock-cycle granularity.

## Phase 0

Phase 0 is the Python behavioral model that benchmarks the CXL-KV Forge-QoS scheduler against B0 Shared FIFO, B1 Priority + Continuous Batching, B2 Chunked Prefill (Sarathi-Serve-style), and the QoS_CxlKvForge target. It generates adversarial W4 workload, emits CSV metrics, and renders plots. Phase 0 is the golden reference for Phase 1 RTL behavior.

## Phase 1 RTL/Vivado readiness

Phase 1 adds a structurally synthesizable SystemVerilog scaffold for the CXL-KV Forge-QoS hardware datapath. It includes AXI4-Stream request/response interfaces, a simplified AXI4-Lite control plane, tenant contracts, token-bucket credit enforcement, per-tenant queues, deadline-aware arbitration, a BRAM-backed mock KV memory path, response generation, counters, XSim simulation scripts, and Vivado project/synthesis Tcl templates.

Run:

```bash
bash scripts/run_xsim.sh
bash scripts/run_vivado_synth.sh
```

See:

- `docs/rtl_phase1_microarchitecture.md`
- `docs/rtl_phase1_verification_plan.md`
- `docs/vivado_phase1_flow.md`
- `docs/phase1_known_limitations.md`

Phase 1 does not implement a real CXL endpoint, PCIe hard IP, DDR/HBM controller, or production driver. Timing closure and bitstream success are not claimed - run the flows and inspect the reports.
