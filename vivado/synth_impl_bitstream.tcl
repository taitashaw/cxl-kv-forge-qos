# -----------------------------------------------------------------------------
# synth_impl_bitstream.tcl
#
# Phase 2 flow:
#   1. Open project + build the block design.
#   2. Run synthesis once (retiming enabled).
#   3. Fork four parallel implementation strategies:
#        Performance_Explore
#        Performance_ExploreWithRemap
#        Performance_ExtraTimingOpt
#        Performance_NetDelay_high
#      Each with POST_ROUTE_PHYS_OPT_DESIGN enabled.
#   4. Collect WNS/TNS/Fmax per strategy into
#      results/impl/phase2_strategy_sweep.md.
#   5. Pick the winning strategy (largest WNS, ties broken by lowest TNS).
#   6. Re-open the winning run and emit bitstream + debug probes to
#      results/impl/kvq_top_wrapper.{bit,ltx}.
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

# ---- Synthesis (retiming enabled) ----
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
close_design

# ---- Strategy sweep ----
set strategies {
  Performance_Explore
  Performance_ExploreWithRemap
  Performance_ExtraTimingOpt
  Performance_NetDelay_high
}

set sweep_runs [list]
foreach strat $strategies {
  set run_name "impl_${strat}"
  if {[llength [get_runs -quiet $run_name]] > 0} {
    delete_runs $run_name
  }
  create_run -name $run_name -parent_run synth_1 \
             -flow "Vivado Implementation 2025" -strategy $strat
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $run_name]
  lappend sweep_runs $run_name
}

# Also disable impl_1 from the default flow so it does not eat a slot.
if {[llength [get_runs -quiet impl_1]] > 0} {
  reset_run impl_1
}

puts "==> Launching parallel impl strategies: $sweep_runs"
launch_runs -jobs 4 {*}$sweep_runs

foreach r $sweep_runs {
  puts "==> Waiting on $r"
  wait_on_run $r
}

# ---- Collect per-strategy metrics ----
set summary_path [file join $impl_dir phase2_strategy_sweep.md]
set summary [open $summary_path w]
puts $summary "# Phase 2 strategy sweep - xczu7ev-ffvc1156-2-e (tournament-tree arbiter)"
puts $summary ""
puts $summary "Target: 400 MHz (2.500 ns)"
puts $summary ""
puts $summary "| strategy | progress | WNS (ns) | TNS (ns) | Failing endpoints | Inferred Fmax (MHz) |"
puts $summary "|---|---|---|---|---|---|"

set best_strat ""
set best_wns -1e9
set best_tns -1e9

foreach r $sweep_runs {
  set strat [string range $r 5 end]
  set progress [get_property PROGRESS [get_runs $r]]
  if {$progress ne "100%"} {
    puts $summary "| $strat | $progress (FAILED) | - | - | - | - |"
    continue
  }
  open_run $r
  set per_dir [file join $impl_dir "strategy_${strat}"]
  file mkdir $per_dir
  report_utilization    -file [file join $per_dir post_route_util.rpt]
  report_timing_summary -file [file join $per_dir post_route_timing.rpt]

  set wns 0.0
  set tns 0.0
  set fep 0
  set rep [report_timing_summary -no_header -return_string -setup]
  foreach line [split $rep "\n"] {
    if {[regexp {Setup\s*:\s*([0-9]+)\s+Failing Endpoints,\s*Worst Slack\s*([-0-9.]+)ns,\s*Total Violation\s*([-0-9.]+)ns} $line _ ef ws tv]} {
      set fep $ef
      set wns $ws
      set tns $tv
      break
    }
    if {[regexp {Setup\s*:\s*([0-9]+)\s+Failing Endpoints,\s*Worst Slack\s*([0-9.]+)ns,\s*Total Violation\s*([0-9.]+)ns} $line _ ef ws tv]} {
      set fep $ef
      set wns $ws
      set tns $tv
      break
    }
  }
  set period [expr {2.5 - $wns}]
  set fmax_mhz 0.0
  if {$period > 0} { set fmax_mhz [expr {1000.0 / $period}] }
  puts $summary "| $strat | done | $wns | $tns | $fep | [format %.1f $fmax_mhz] |"

  # Track winner
  if {$wns > $best_wns || ($wns == $best_wns && $tns > $best_tns)} {
    set best_wns $wns
    set best_tns $tns
    set best_strat $strat
  }
  close_design
}

puts $summary ""
puts $summary "Winning strategy: **$best_strat** (WNS = $best_wns ns, TNS = $best_tns ns)"
close $summary
puts "==> Strategy sweep complete. Best: $best_strat (WNS=$best_wns ns)"

# ---- Bitstream from the winning strategy ----
if {$best_strat ne ""} {
  set winner_run "impl_${best_strat}"
  puts "==> Generating bitstream on $winner_run"
  launch_runs $winner_run -to_step write_bitstream -jobs 4
  wait_on_run $winner_run
  if {[get_property PROGRESS [get_runs $winner_run]] ne "100%"} {
    puts "Bitstream generation failed."
    exit 4
  }

  open_run $winner_run
  write_debug_probes -force [file join $impl_dir kvq_top_wrapper.ltx]
  close_design

  set runs_dir [file join $proj_dir ${proj_name}.runs $winner_run]
  foreach pattern {*.bit *.ltx} {
    foreach f [glob -nocomplain -directory $runs_dir $pattern] {
      set base [file tail $f]
      set target [string map {kvq_phase1_bd_wrapper kvq_top_wrapper} $base]
      file copy -force $f [file join $impl_dir $target]
    }
  }

  # Also publish the winning strategy's reports as the canonical ZCU102 ones
  file copy -force [file join $impl_dir strategy_${best_strat} post_route_util.rpt] \
                   [file join $impl_dir zcu102_post_route_util.rpt]
  file copy -force [file join $impl_dir strategy_${best_strat} post_route_timing.rpt] \
                   [file join $impl_dir zcu102_post_route_timing.rpt]
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
  $summary_path \
] {
  if {[file exists $f]} { puts "  OK   $f" } else { puts "  MISS $f" }
}
