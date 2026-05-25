# -----------------------------------------------------------------------------
# closure_build.tcl
#
# Single-strategy Phase 2 signoff build. Re-uses the project + BD created by
# synth_impl_bitstream.tcl. Only the WINNING strategy from the sweep runs.
# Assumes create_block_design.tcl has been edited to target the closure
# frequency (Fmax * 0.95 of the sweep winner).
#
# Strategy: Performance_NetDelay_high (selected by the Phase 2 sweep).
# -----------------------------------------------------------------------------

set proj_root [file normalize [pwd]]
set proj_dir  [file join $proj_root build vivado kvq_phase1]
set xpr       [file join $proj_dir kvq_phase1.xpr]
set synth_dir [file join $proj_root results synth]
set impl_dir  [file join $proj_root results impl]
file mkdir $impl_dir

if {![file exists $xpr]} {
  puts "Project not found at $xpr; run create_project.tcl first."
  exit 1
}

open_project $xpr

puts "==> Sourcing create_block_design.tcl (BD now targets 300 MHz)"
source [file join $proj_root vivado create_block_design.tcl]

# ---- Synthesis (retiming enabled) ----
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

puts "==> Re-running synthesis at the closure clock target"
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

# ---- Insert debug core on MARK_DEBUG nets so write_debug_probes after
#      impl produces a real .ltx ----
set dbg_nets [get_nets -hierarchical -filter {MARK_DEBUG == TRUE}]
if {[llength $dbg_nets] > 0} {
  puts "==> Inserting ILA on [llength $dbg_nets] MARK_DEBUG nets"
  set kvq_clk_pin [get_pins -quiet kvq_phase1_bd_i/kvq_top_0/inst/clk]
  set ila_clk ""
  if {[llength $kvq_clk_pin] > 0} {
    set ila_clk [get_nets -of_objects $kvq_clk_pin -quiet]
  }
  if {[llength $ila_clk] == 0} {
    set ila_clk [lindex [get_nets -hier -filter {NAME =~ "*clk_out1*"}] 0]
  }
  if {[llength $ila_clk] > 0} {
    create_debug_core u_ila_dbg ila
    set_property C_DATA_DEPTH        1024  [get_debug_cores u_ila_dbg]
    set_property C_TRIGIN_EN         false [get_debug_cores u_ila_dbg]
    set_property C_TRIGOUT_EN        false [get_debug_cores u_ila_dbg]
    set_property C_ADV_TRIGGER       false [get_debug_cores u_ila_dbg]
    set_property C_INPUT_PIPE_STAGES 1     [get_debug_cores u_ila_dbg]
    set_property C_EN_STRG_QUAL      false [get_debug_cores u_ila_dbg]
    set_property port_width 1              [get_debug_ports u_ila_dbg/clk]
    connect_debug_port u_ila_dbg/clk $ila_clk
    set idx 0
    foreach net $dbg_nets {
      if {$idx > 0} { create_debug_port u_ila_dbg probe }
      set_property port_width 1 [get_debug_ports u_ila_dbg/probe${idx}]
      connect_debug_port u_ila_dbg/probe${idx} $net
      incr idx
    }
    puts "==> Debug core attached to $idx probes"
  }
}

close_design

# ---- Impl with winning strategy ----
set winner "Performance_NetDelay_high"
set winner_run "impl_${winner}"

if {[llength [get_runs -quiet $winner_run]] > 0} {
  reset_run $winner_run
} else {
  create_run -name $winner_run -parent_run synth_1 \
             -flow "Vivado Implementation 2025" -strategy $winner
}
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $winner_run]

puts "==> Closure impl with strategy: $winner"
launch_runs $winner_run -jobs 4
wait_on_run $winner_run
if {[get_property PROGRESS [get_runs $winner_run]] ne "100%"} {
  puts "Impl failed."
  exit 3
}

open_run $winner_run
report_utilization    -file [file join $impl_dir zcu102_post_route_util.rpt]
report_timing_summary -file [file join $impl_dir zcu102_post_route_timing.rpt]

# Pull WNS/TNS/Fep from the post-route summary
set wns 0.0
set tns 0.0
set fep 0
set rep [report_timing_summary -no_header -return_string -setup]
foreach line [split $rep "\n"] {
  if {[regexp {Setup\s*:\s*([0-9]+)\s+Failing Endpoints,\s*Worst Slack\s*([-0-9.]+)ns,\s*Total Violation\s*([-0-9.]+)ns} $line _ ef ws tv]} {
    set fep $ef; set wns $ws; set tns $tv; break
  }
  if {[regexp {Setup\s*:\s*([0-9]+)\s+Failing Endpoints,\s*Worst Slack\s*([0-9.]+)ns,\s*Total Violation\s*([0-9.]+)ns} $line _ ef ws tv]} {
    set fep $ef; set wns $ws; set tns $tv; break
  }
}
puts ""
puts "==> Closure summary at 300 MHz target:"
puts "    WNS: $wns ns"
puts "    TNS: $tns ns"
puts "    Failing endpoints: $fep"
if {$wns >= 0.0 && $tns >= 0.0 && $fep == 0} {
  puts "    *** TIMING CLOSED ***"
} else {
  puts "    *** TIMING DID NOT CLOSE ***"
}

close_design

# ---- Bitstream + .ltx ----
puts "==> Generating bitstream"
launch_runs $winner_run -to_step write_bitstream -jobs 4
wait_on_run $winner_run
if {[get_property PROGRESS [get_runs $winner_run]] ne "100%"} {
  puts "Bitstream generation failed."
  exit 4
}

open_run $winner_run
write_debug_probes -force [file join $impl_dir kvq_top_wrapper.ltx]
close_design

set runs_dir [file join $proj_dir kvq_phase1.runs $winner_run]
foreach pattern {*.bit *.ltx} {
  foreach f [glob -nocomplain -directory $runs_dir $pattern] {
    set base [file tail $f]
    set target [string map {kvq_phase1_bd_wrapper kvq_top_wrapper} $base]
    file copy -force $f [file join $impl_dir $target]
  }
}

puts ""
puts "==> Artifact check:"
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
