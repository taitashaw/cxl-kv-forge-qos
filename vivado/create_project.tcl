# -----------------------------------------------------------------------------
# create_project.tcl
# Phase 1 Vivado project bootstrap. Targets ZCU102 (xczu9eg-ffvb1156-2-e).
# Adds RTL sources, constraints, and sets kvq_top as top. Save the project to
# build/vivado/kvq_phase1. Subsequent runs use synth_impl_bitstream.tcl.
# -----------------------------------------------------------------------------

set proj_root [file normalize [pwd]]
set build_dir [file join $proj_root build vivado]
set proj_name "kvq_phase1"
set proj_dir  [file join $build_dir $proj_name]
file mkdir $build_dir

# Default part: xczu7ev-ffvc1156-2-e (largest license-eligible MPSoC in this
# Vivado install, 230k LUTs, 3.3x xczu3eg). With the 3-stage pipelined RTL
# and Vivado retiming enabled in synth_impl_bitstream.tcl, the placer's
# headroom (~8% utilization) lets retiming rebalance the arbiter cone.
# xczu9eg remains license-blocked; xczu3eg is still accessible via
# VIVADO_PART=xczu3eg-sbva484-1-e for a smaller-part sanity check.
if {[info exists ::env(VIVADO_PART)]} {
  set part $::env(VIVADO_PART)
} else {
  set part "xczu7ev-ffvc1156-2-e"
}
puts "==> Target part: $part"

if {[file exists [file join $proj_dir ${proj_name}.xpr]]} {
  open_project [file join $proj_dir ${proj_name}.xpr]
} else {
  create_project $proj_name $proj_dir -part $part -force
}

set rtl_dir [file join $proj_root rtl]
set viv_dir [file join $proj_root vivado]

# Add RTL in dependency order
set rtl_files [list \
  [file join $rtl_dir kvq_pkg.sv] \
  [file join $rtl_dir kvq_bram_model.sv] \
  [file join $rtl_dir kvq_token_bucket.sv] \
  [file join $rtl_dir kvq_request_parser.sv] \
  [file join $rtl_dir kvq_tenant_contract_table.sv] \
  [file join $rtl_dir kvq_credit_engine.sv] \
  [file join $rtl_dir kvq_per_tenant_queue_manager.sv] \
  [file join $rtl_dir kvq_deadline_arbiter.sv] \
  [file join $rtl_dir kvq_latency_tracker.sv] \
  [file join $rtl_dir kvq_memory_engine.sv] \
  [file join $rtl_dir kvq_response_builder.sv] \
  [file join $rtl_dir kvq_error_handler.sv] \
  [file join $rtl_dir kvq_sla_monitor.sv] \
  [file join $rtl_dir kvq_perf_counters.sv] \
  [file join $rtl_dir kvq_axil_regs.sv] \
  [file join $rtl_dir kvq_top.sv] \
  [file join $rtl_dir kvq_top_bd_wrap.v]
]

add_files -norecurse $rtl_files

# Constraints
add_files -fileset constrs_1 -norecurse [file join $viv_dir constraints.xdc]

foreach f [get_files *.sv] {
  set_property file_type "SystemVerilog" $f
}
update_compile_order -fileset sources_1

# Do NOT pin top here. For the BD-wrapped flow, top is set to the BD
# wrapper inside create_block_design.tcl. We also skip the elaborate-only
# syntax check; it duplicates what synth_design will do and would
# otherwise leave the project's "current_design" pointing at a non-BD top.

puts "Project ready: $proj_dir (top will be set by create_block_design.tcl)"
