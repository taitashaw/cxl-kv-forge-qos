# CXL-KV Forge-QoS - Phase 1 Known Limitations

Phase 1 is a hardware baseline, not a production endpoint. The following limitations are explicit and intentional.

## CXL / PCIe surface

- No real CXL endpoint. The Phase 1 RTL emulates the CXL request path using AXI4-Stream.
- No PCIe hard IP. The Phase 1 RTL does not include a Versal Premium / Agilex 7 R-Tile / U280 PCIe controller.
- No real CXL.mem or CXL.cache protocol handling. Opcode semantics are KV-cache-only.

## Memory surface

- No DDR4 / DDR5 controller. The mock memory is a synchronous BRAM.
- No HBM controller. Future targets (U280, U55C) require swapping `kvq_bram_model` for a Vivado HBM controller wrapper.
- No ECC. The BRAM model does not provide single-error correction or double-error detection.
- No real cache eviction policy. `KVQ_OP_EVICT` is acknowledged but performs no state change in Phase 1.
- The valid-bit table is the only liveness signal - it is reset by the soft-reset pulse, not by line-level invalidation.

## Control plane

- Simplified AXI4-Lite. `wstrb` is ignored, `bresp`/`rresp` are always OKAY.
- No interrupt output. Counter rollover and SLA breaches are not surfaced as a hard interrupt - operators poll AXI4-Lite status registers.
- Contract readback is write-only in MVP. Reads to the 0x1000 window return zero.

## Datapath

- Single-issue memory engine. The Phase 1 pipeline accepts one outstanding read or write at a time. Real throughput requires a multi-outstanding tracker, deferred to Phase 2.
- Per-tenant queues capped at 16 entries each. Sized for ZCU102 distributed RAM; larger queues require BRAM packing.
- Maximum 8 tenants (`MAX_TENANTS = 8`). Increasing the cap is a parameter change but has area / arbitration-depth implications.
- Arbitration uses request-side `deadline_cycles` as a slack surrogate. True per-request enqueue-time tracking lands in Phase 2.

## Observability

- No percentile or histogram counters. Phase 0 Python computes p50/p95/p99 from CSV traces.
- No per-tenant counter banks. The SLA monitor is global-only.
- No streaming telemetry over AXI4-Stream. Observability comes through AXI4-Lite reads and the ILA template in the block design.

## Tooling and infrastructure

- No production driver. There is no Linux kernel driver, no userspace runtime, no Python control loop.
- No measured timing closure. `synth_impl_bitstream.tcl` runs the flow, but Phase 1 does not assert WNS/TNS values - the operator must inspect `impl_timing_summary.rpt`.
- No bitstream success claim. `bash scripts/run_vivado_synth.sh` runs the flow; success of the underlying tools does not imply hardware bring-up has been validated.
- Block design Tcl is a TEMPLATE. Address map, DMA buffer width, and ILA probe wiring are TODO markers.
- IP packager interface inference is fragile across Vivado versions. Operators must validate AXI4-Stream / AXI4-Lite interface mapping in the GUI.

## What lands in Phase 2

- Real CXL endpoint integration (Versal Premium / Agilex 7 R-Tile).
- Multi-outstanding memory engine with per-request tracking table.
- Per-tenant counter banks and histogram support.
- Random / constrained-random regression with coverage closure.
- Full 45-test directed matrix from the original Phase 1 spec.
- Production driver and Python control-plane integration.
