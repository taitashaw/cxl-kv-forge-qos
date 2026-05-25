# -----------------------------------------------------------------------------
# synth_impl_bitstream.tcl
#
# Drives the BD-wrapped flow end-to-end:
#   1. Open the project created by create_project.tcl
#   2. Source create_block_design.tcl to build the BD around kvq_top
#   3. Synthesize the BD wrapper as the top
#   4. Implement (place + route)
#   5. Generate bitstream + .ltx debug probes file
#
# Artifacts land under results/synth/ and results/impl/:
#   - results/synth/zcu102_synth_util.rpt
#   - results/synth/zcu102_timing_summary.rpt
#   - results/impl/zcu102_post_route_timing.rpt
#   - results/impl/zcu102_post_route_util.rpt
#   - results/impl/kvq_top_wrapper.bit
#   - results/impl/kvq_top_wrapper.ltx
# -----------------------------------------------------------------------------

set proj_root [file normalize [pwd]]
set build_dir [file join $proj_root build vivado]
set proj_name "kvq_phase1"
set proj_dir  [file join $build_dir $proj_name]
set xpr       [file join $proj_dir ${proj_name}.xpr]
set synth_dir [file join $proj_root results synth]
set impl_dir  [file join $proj_root results impl]
file mkdir $synth_dir
file mkdir $impl_dir

if {![file exists $xpr]} {
  puts "Project not found at $xpr; run create_project.tcl first."
  exit 1
}

open_project $xpr

# ---- Build / refresh block design ----
puts "==> Sourcing create_block_design.tcl"
source [file join $proj_root vivado create_block_design.tcl]

# ---- Synthesis ----
# Enable retiming so the arbiter's stage-3 output registers (tagged with
# retiming_backward = 1 in rtl/kvq_deadline_arbiter.sv) can be pulled
# backward through the 42-level winner-mux cone.
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

puts "==> Launch synthesis (retiming enabled)"
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
  puts "Synthesis failed."
  exit 2
}

open_run synth_1 -name synth_1
report_utilization     -file [file join $synth_dir zcu102_synth_util.rpt]
report_timing_summary  -file [file join $synth_dir zcu102_timing_summary.rpt]

# -------------------------------------------------------------------------
# Post-synth debug-core insertion. MARK_DEBUG-tagged nets inside kvq_top
# get attached to a fresh ILA so HW Manager can see them via the .ltx
# file produced after impl.
# -------------------------------------------------------------------------
set dbg_nets [get_nets -hierarchical -filter {MARK_DEBUG == TRUE}]
if {[llength $dbg_nets] > 0} {
  puts "==> Inserting ILA on [llength $dbg_nets] MARK_DEBUG net(s)"
  # Locate the 250 MHz design clock - the kvq_top_0/inst/clk pin's source net.
  set kvq_clk_pin [get_pins -quiet kvq_phase1_bd_i/kvq_top_0/inst/clk]
  set ila_clk ""
  if {[llength $kvq_clk_pin] > 0} {
    set ila_clk [get_nets -of_objects $kvq_clk_pin -quiet]
  }
  if {[llength $ila_clk] == 0} {
    set ila_clk [lindex [get_nets -hier -filter {NAME =~ "*clk_out1*"}] 0]
  }
  if {[llength $ila_clk] > 0} {
    puts "==> ILA clock net: $ila_clk"
    create_debug_core u_ila_dbg ila
    set_property C_DATA_DEPTH        1024  [get_debug_cores u_ila_dbg]
    set_property C_TRIGIN_EN         false [get_debug_cores u_ila_dbg]
    set_property C_TRIGOUT_EN        false [get_debug_cores u_ila_dbg]
    set_property C_ADV_TRIGGER       false [get_debug_cores u_ila_dbg]
    set_property C_INPUT_PIPE_STAGES 1     [get_debug_cores u_ila_dbg]
    set_property C_EN_STRG_QUAL      false [get_debug_cores u_ila_dbg]
    set_property port_width 1              [get_debug_ports u_ila_dbg/clk]
    connect_debug_port u_ila_dbg/clk $ila_clk
    # One probe per bit net. The HW Manager groups them back into buses
    # by net name via the .ltx file.
    set idx 0
    foreach net $dbg_nets {
      if {$idx > 0} { create_debug_port u_ila_dbg probe }
      set_property port_width 1 [get_debug_ports u_ila_dbg/probe${idx}]
      connect_debug_port u_ila_dbg/probe${idx} $net
      incr idx
    }
    puts "==> Debug core u_ila_dbg attached to $idx probes"
    # NOTE: do NOT save_constraints here. The debug-core net references are
    # specific to this synth run; saving them into constraints.xdc would
    # poison the next build (stale net paths -> Chipscope 16-213 errors).
    # The runtime debug core is applied to this run via the in-memory
    # netlist, and write_debug_probes below captures the .ltx for HW Manager.
  } else {
    puts "WARN: could not locate kvq design clock for debug-core insertion"
  }
} else {
  puts "WARN: no MARK_DEBUG nets found; ILA not inserted"
}
close_design

# Enable phys_opt with AggressiveExplore so timing-critical paths
# (especially the retimed arbiter cone) get further rebalanced post-place.
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

puts "==> Launch implementation (phys_opt AggressiveExplore)"
reset_run impl_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
  puts "Implementation failed."
  exit 3
}

open_run impl_1
report_utilization     -file [file join $impl_dir zcu102_post_route_util.rpt]
report_timing_summary  -file [file join $impl_dir zcu102_post_route_timing.rpt]
write_debug_probes -force [file join $impl_dir kvq_top_wrapper.ltx]
close_design

# ---- Bitstream ----
puts "==> Generate bitstream"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
  puts "Bitstream generation failed."
  exit 4
}

# Copy bitstream + ltx to results/impl/
set runs_impl [file join $proj_dir ${proj_name}.runs impl_1]
foreach pattern {*.bit *.ltx} {
  foreach f [glob -nocomplain -directory $runs_impl $pattern] {
    set base [file tail $f]
    # Vivado names the bitstream after the project's top; rename to the
    # canonical kvq_top_wrapper.* artifact name.
    set target [string map {kvq_phase1_bd_wrapper kvq_top_wrapper} $base]
    file copy -force $f [file join $impl_dir $target]
  }
}

puts ""
puts "==> Build artifacts:"
foreach f [list \
  [file join $synth_dir zcu102_synth_util.rpt] \
  [file join $synth_dir zcu102_timing_summary.rpt] \
  [file join $impl_dir  zcu102_post_route_util.rpt] \
  [file join $impl_dir  zcu102_post_route_timing.rpt] \
  [file join $impl_dir  kvq_top_wrapper.bit] \
  [file join $impl_dir  kvq_top_wrapper.ltx] \
] {
  if {[file exists $f]} { puts "  OK   $f" } else { puts "  MISS $f" }
}
puts ""
puts "Inspect timing in zcu102_post_route_timing.rpt - WNS/TNS are not"
puts "asserted by this script."
