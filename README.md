# CXL-KV Forge-QoS

Hardware-Enforced SLA Controller for Multi-Tenant LLM KV-Cache Access.

Software LLM schedulers operate at millisecond to tens-of-milliseconds granularity, while KV-cache memory contention occurs at sub-microsecond granularity through queue head-of-line blocking, memory-bank contention, cache-line eviction, and burst interference. CXL-KV Forge-QoS closes this timescale gap by enforcing tenant credits, token-bucket bandwidth limits, queue isolation, deadline-aware arbitration, and SLA telemetry at AXI/CXL clock-cycle granularity.

## Phase 2.1 signoff status

| metric | value |
|---|---|
| Reference part | xczu7ev-ffvc1156-2-e (largest license-eligible MPSoC) |
| Closed-timing clock | **350 MHz** (2.857 ns) |
| Post-route WNS | **+0.004 ns (MET)** |
| Post-route TNS / failing endpoints | **0 / 0** |
| Datapath width (AXIS request/response) | 256 bits |
| Sustained throughput | **256 × 350 / 1000 = 89.6 Gb/s** per AXIS stream (request + response = 179.2 Gb/s aggregate) |
| Arbitration-path latency | ~10-11 cycles ≈ **28.6 to 31.4 ns** at 350 MHz |
| Pipeline | 2-stage qmgr + 3-stage tournament-tree arbiter + 2-stage token bucket |
| XSim regression | 12 / 12 PASS |
| Bitstream | `results/impl/kvq_top_wrapper.bit` (19.3 MB) |
| Debug probes | `results/impl/kvq_top_wrapper.ltx` (121 KB, 111 MARK_DEBUG nets) |

Full closure narrative and four-build progression (Phase 1 → Phase 2.1) in `docs/architecture.md`. Final signoff doc: `results/PHASE2_1_FINAL.md`.

## Visual artifacts

![Integrated block design](docs/block_design/kvq_top_bd.png)

*Integrated block design on xczu7ev: Cortex-A53 PS (`ps_e_0`) drives two AXI SmartConnects — `smartconnect_axil` (PS HPM0_LPD → kvq_top_0 s_axi_lite) and `smartconnect_dma_ctrl` (PS HPM0_FPD → axi_dma_0 control). DMA data plane (`smartconnect_data`) bridges axi_dma_0 MM2S/S2MM streams to PS S_AXI_HP0_FPD. `clk_wiz_0` multiplies PS PL_CLK0 (100 MHz) up to the 350 MHz design clock. PNG generated from the Vivado-exported PDF via pdftocairo at 150 DPI.*

PDF and SVG versions also under `docs/block_design/` for higher-fidelity zoom.

## Visual artifacts — pending

Waveform PNGs for the XSim regression (`docs/waveforms/qos_phase1_bringup.png`, `docs/waveforms/qos_w4_contention.png`) are not yet generated. The render Tcl and shell wrapper are written and committed (`sim/xsim/render_waveform.tcl`, `scripts/render_waveform.sh`); on this host they require `xvfb-run` + Vivado's `xsim --gui` mode to host the wave window so `write_wave_image` can render. That combination didn't return cleanly inside the available time budget for the Phase 2.2 sprint and is held for a follow-up:

```bash
# When picked up, the existing scripts run like this:
xvfb-run -a -s "-screen 0 1920x1200x24" bash scripts/render_waveform.sh
```

Expected outputs: two PNGs, ~2 µs and ~4-6 µs windows of the testbench run that cover reset / first-AXIL-program / first-arrival, and the multi-tenant priority + deadline contention spike (T9 / T10 of the 12-test directed regression).

## Phase 0

Phase 0 is the Python behavioral model that benchmarks the CXL-KV Forge-QoS scheduler against B0 Shared FIFO, B1 Priority + Continuous Batching, B2 Chunked Prefill (Sarathi-Serve-style), and the QoS_CxlKvForge target. It generates adversarial W4 workload, emits CSV metrics, and renders plots. Phase 0 is the golden reference for Phase 1 RTL behavior. The Phase 0 simulator works in microsecond workload time (`Request.arrival_us` / `service_us`), not in RTL cycles, so Phase 0 plots are independent of RTL Fmax.

All four Phase 0 schedulers complete every queued request within the sim window on a single shared compute server; differentiation is in per-tenant latency (p50 / p95 / p99) and deadline-miss behavior, not in aggregate throughput. The identical 5,668 req/s in `results/adversarial_w4_summary.csv` is mathematically expected — see `results/methodology_audit.md` for the file:line walkthrough.

Run:

```bash
python3 sim/run_benchmark.py
```

Outputs: `results/adversarial_w4_summary.csv`, `results/plots/{adversarial_w4_baseline_comparison,w4_fairness_per_tenant,w4_jains_index}.png`.

## Phase 1 RTL/Vivado readiness

Phase 1 adds a structurally synthesizable SystemVerilog scaffold for the CXL-KV Forge-QoS hardware datapath. It includes AXI4-Stream request/response interfaces, a simplified AXI4-Lite control plane, tenant contracts, token-bucket credit enforcement, per-tenant queues, deadline-aware arbitration, a BRAM-backed mock KV memory path, response generation, counters, XSim simulation scripts, and Vivado project/synthesis Tcl templates.

Run:

```bash
bash scripts/run_xsim.sh         # 12-test directed regression
bash scripts/run_vivado_synth.sh # 4-strategy sweep + winning-strategy bitstream
```

See `docs/rtl_phase1_microarchitecture.md`, `docs/rtl_phase1_verification_plan.md`, `docs/vivado_phase1_flow.md`, `docs/phase1_known_limitations.md`, `docs/architecture.md`, `docs/module_specs.md`.

## Phase 2 and Phase 2.1 — what changed structurally

| sprint | RTL change | Closed-timing Fmax |
|---|---|---|
| Phase 1 baseline (xczu3eg) | single-cycle 8-way arbiter | 80 MHz |
| Phase 1 retiming (xczu7ev) | + post-comb register at arbiter output | 86 MHz |
| Phase 2 (xczu7ev) | tournament-tree arbiter (3-level pairwise) | **305.9 MHz** |
| **Phase 2.1 (xczu7ev)** | **+ 2-stage token-bucket pipeline** | **350 MHz** |

Phase 3 (out of scope here): port to Agilex 7 -3 speed grade for further headroom.

## Limitations (still true)

- No real CXL endpoint, PCIe hard IP, DDR/HBM controller, or production driver.
- xczu9eg (ZCU102) remains license-blocked in this Vivado install — closure verified on xczu7ev as the largest licensed alternative.
- After running Phase 2 / Phase 2.1 closure, `vivado/constraints.xdc` is polluted with debug-net references from the `save_constraints` step. Reset via `git checkout HEAD -- vivado/constraints.xdc` before the next clean rebuild.
