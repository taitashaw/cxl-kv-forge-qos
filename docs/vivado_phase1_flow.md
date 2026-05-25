# CXL-KV Forge-QoS - Phase 1 Vivado Flow

## Entry points

| Script                          | Purpose                                                  |
|---------------------------------|----------------------------------------------------------|
| `bash scripts/run_xsim.sh`      | Compile RTL + TB, elaborate, run XSim, write summary.    |
| `bash scripts/run_vivado_synth.sh` | Drive Vivado in batch: project create -> synth -> impl -> bitstream. |
| `vivado/create_project.tcl`     | Bootstrap the project under `build/vivado/kvq_phase1`.   |
| `vivado/synth_impl_bitstream.tcl` | Run synthesis, implementation, bitstream and emit reports. |
| `vivado/package_ip.tcl`         | Package `kvq_top` as Vivado IP (`shawsilicon.ai:user:cxl_kv_forge_qos:0.1`). |
| `vivado/create_block_design.tcl` | Template block design: PS + DMA + IP + ILA + clocks/resets. |

## Expected outputs

Under `results/rtl_sim/`:

- `phase1_xsim_summary.csv` - pass/fail line per test.
- `xsim_compile.log`, `xsim_elab.log`, `xsim.log` - tool transcripts.

Under `results/vivado/`:

- `synth_utilization.rpt`, `synth_timing_summary.rpt` - post-synthesis numbers.
- `impl_utilization.rpt`,  `impl_timing_summary.rpt`  - post-implementation numbers.
- `vivado_create_project.log`, `vivado_synth_impl.log` - tool transcripts.

The Vivado driver does NOT assert success - it surfaces tool exit codes and points the operator at the reports.

## Known Vivado limitations

- The Phase 1 standalone constraints (`vivado/constraints.xdc`) declare clock period intent only. Real I/O pin constraints come from the block design wrapper (ZCU102 PS-driven AXI). Standalone runs may report unconstrained I/O timing.
- `package_ip.tcl` cannot fully infer AXI4-Stream `tlast` and AXI4-Lite `wstrb` mappings in older Vivado revisions. Open the packager GUI and confirm the mapping before publishing.
- The block design Tcl is a TEMPLATE. Address-map verification, AXI DMA buffer width, and ILA probe wiring are explicit TODOs.
- Vivado batch mode silently continues past some recoverable warnings. Always inspect both `*_timing_summary.rpt` files for WNS/TNS, not just exit codes.
- Bitstream generation can succeed even when impl timing is negative; the driver does not gate on WNS. Operators must check timing reports for closure before claiming production-readiness.
- ZCU102 part string is fixed in `create_project.tcl` (`xczu9eg-ffvb1156-2-e`). Adapting to U280/U55C/Versal requires editing the part property and re-running the constraints story.
