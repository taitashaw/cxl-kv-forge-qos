# -----------------------------------------------------------------------------
# closure_inmem.tcl
#
# Phase 2.1 closure: synth -> insert debug core in-memory -> opt -> place ->
# phys_opt -> route -> post-route phys_opt -> write_bitstream + write_debug_probes,
# ALL in the same Vivado session via direct *_design commands (project-mode
# launch_runs spawns child Vivado processes that lose in-memory debug-core
# state). save_constraints is NEVER called - constraints.xdc stays canonical.
#
# Strategy: Performance_ExtraTimingOpt's directives applied via set_property
# on the in-memory design.
# -----------------------------------------------------------------------------

set proj_root [file normalize [pwd]]
set proj_dir  [file join $proj_root build vivado kvq_phase1]
set xpr       [file join $proj_dir kvq_phase1.xpr]
set synth_dir [file join $proj_root results synth]
set impl_dir  [file join $proj_root results impl]
file mkdir $synth_dir
file mkdir $impl_dir

if {![file exists $xpr]} {
  puts "Project not found at $xpr; run create_project.tcl first."
  exit 1
}

open_project $xpr

puts "==> Sourcing create_block_design.tcl (BD targets 350 MHz)"
source [file join $proj_root vivado create_block_design.tcl]

# ---------------------------------------------------------------------------
# Synthesis (project-mode run; we still use synth_1 for parallelism on the
# IP-level synth_runs)
# ---------------------------------------------------------------------------
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-global_retiming on} -objects [get_runs synth_1]

puts "==> Launching synth_1 with global retiming"
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
  puts "Synthesis failed."
  exit 2
}

# Open the synthesized design IN-MEMORY for the rest of the flow
open_run synth_1 -name synth_1
report_utilization     -file [file join $synth_dir zcu102_synth_util.rpt]
report_timing_summary  -file [file join $synth_dir zcu102_timing_summary.rpt]

# ---------------------------------------------------------------------------
# Insert debug core on MARK_DEBUG nets (in-memory; survives because we
# don't close/reopen the design)
# ---------------------------------------------------------------------------
set dbg_nets [get_nets -hierarchical -filter {MARK_DEBUG == TRUE}]
puts "==> Found [llength $dbg_nets] MARK_DEBUG nets"
if {[llength $dbg_nets] > 0} {
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
    puts "==> Debug core u_ila_dbg attached to $idx probes (in-memory)"
  }
}

# ---------------------------------------------------------------------------
# In-memory impl: opt_design, place_design, phys_opt_design, route_design,
# post-route phys_opt. Use Performance_ExtraTimingOpt directives.
# ---------------------------------------------------------------------------
puts "==> opt_design (ExtraTimingOpt directive)"
opt_design -directive ExploreWithRemap

puts "==> place_design (ExtraTimingOpt directive)"
place_design -directive ExtraTimingOpt

puts "==> phys_opt_design (AggressiveExplore)"
phys_opt_design -directive AggressiveExplore

puts "==> route_design (NoTimingRelaxation - the route directive Vivado pairs with the ExtraTimingOpt strategy)"
route_design -directive NoTimingRelaxation

puts "==> post-route phys_opt_design"
phys_opt_design -directive AggressiveExplore

# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------
report_utilization    -file [file join $impl_dir zcu102_post_route_util.rpt]
report_timing_summary -file [file join $impl_dir zcu102_post_route_timing.rpt]

# Extract WNS / TNS / failing endpoints for the design clock specifically
set clk_name "clk_out1_kvq_phase1_bd_clk_wiz_0_0"
set wns 0.0; set tns 0.0; set fep 0
set tp [report_timing -setup -nworst 1 -no_header -return_string \
         -group $clk_name]
foreach line [split $tp "\n"] {
  if {[regexp {Slack.*?:\s*(-?[0-9.]+)} $line _ s]} {
    set wns $s
    break
  }
}
# Pull TNS / failing endpoints by string filter
set tsum [report_timing_summary -no_header -return_string -setup]
foreach line [split $tsum "\n"] {
  if {[regexp [format {%s\s+([-0-9.]+)\s+([-0-9.]+)\s+([0-9]+)} $clk_name] $line _ w t f]} {
    set wns $w; set tns $t; set fep $f
    break
  }
}

puts ""
puts "==> Closure summary at 350 MHz target on $clk_name:"
puts "    WNS: $wns ns"
puts "    TNS: $tns ns"
puts "    Failing endpoints: $fep"
if {$wns >= 0.0 && $fep == 0} {
  puts "    *** TIMING CLOSED ***"
} else {
  puts "    *** TIMING DID NOT CLOSE ***"
}

# ---------------------------------------------------------------------------
# Bitstream + .ltx (both directly from this in-memory session)
# ---------------------------------------------------------------------------
puts "==> write_bitstream"
write_bitstream -force [file join $impl_dir kvq_top_wrapper.bit]
puts "==> write_debug_probes"
write_debug_probes -force [file join $impl_dir kvq_top_wrapper.ltx]

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
