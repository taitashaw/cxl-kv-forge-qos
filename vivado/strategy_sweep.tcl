# -----------------------------------------------------------------------------
# strategy_sweep.tcl
#
# Runs synth once, then four parallel implementation runs each with a
# different performance-oriented strategy. Captures WNS/TNS/util to
# results/impl/phase2_strategy_sweep.md and to per-strategy report files
# under results/impl/strategy_<name>/.
#
# Strategies probed:
#   Performance_Explore
#   Performance_ExploreWithRemap
#   Performance_ExtraTimingOpt
#   Performance_NetDelay_high
#
# Run after synth_impl_bitstream.tcl's synth_design has been done. This
# script opens the project, then forks parallel impl runs.
# -----------------------------------------------------------------------------

set proj_root [file normalize [pwd]]
set proj_dir  [file join $proj_root build vivado kvq_phase1]
set xpr       [file join $proj_dir kvq_phase1.xpr]
set impl_dir  [file join $proj_root results impl]
file mkdir $impl_dir

open_project $xpr

# Ensure synth_1 is done; we will reuse it as the parent run for all 4 impls.
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
  puts "ERROR: synth_1 has not completed yet. Run synth_impl_bitstream.tcl first."
  exit 1
}

set strategies {
  Performance_Explore
  Performance_ExploreWithRemap
  Performance_ExtraTimingOpt
  Performance_NetDelay_high
}

# Build the per-strategy impl runs
set runs_to_launch [list]
foreach strat $strategies {
  set run_name "impl_${strat}"
  if {[llength [get_runs -quiet $run_name]] == 0} {
    create_run -name $run_name -parent_run synth_1 \
               -flow "Vivado Implementation 2025" -strategy $strat
  } else {
    reset_run $run_name
  }
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $run_name]
  lappend runs_to_launch $run_name
}

# Launch all four in parallel (Vivado will schedule by available cores)
puts "==> Launching parallel impl strategies: $runs_to_launch"
launch_runs -jobs 4 {*}$runs_to_launch

# Wait for all four
foreach r $runs_to_launch {
  puts "==> Waiting on $r"
  wait_on_run $r
}

# Collect results
set summary [open [file join $impl_dir phase2_strategy_sweep.md] w]
puts $summary "# Phase 2 strategy sweep on xczu7ev-ffvc1156-2-e (tournament-tree arbiter)\n"
puts $summary "Target: 2.500 ns (400 MHz)\n"
puts $summary "| strategy | progress | WNS (ns) | TNS (ns) | Failing endpoints | Fmax (MHz) |"
puts $summary "|---|---|---|---|---|---|"

foreach r $runs_to_launch {
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
  # Parse WNS
  set tc [get_timing_paths -max_paths 1 -setup -nworst 1 \
            -filter {GROUP =~ "*clk_wiz_0*"}]
  set wns 0.0
  if {[llength $tc] > 0} {
    set wns [get_property SLACK [lindex $tc 0]]
  }
  # Setup TNS / failing-endpoints summary
  set rep [report_timing_summary -no_header -return_string -setup]
  set tns 0.0
  set fep 0
  foreach line [split $rep "\n"] {
    if {[regexp {Setup\s*:\s*([0-9]+)\s+Failing Endpoints,\s*Worst Slack\s*([-0-9.]+)ns,\s*Total Violation\s*([-0-9.]+)ns} $line _ ef ws tv]} {
      set fep $ef
      set wns $ws
      set tns $tv
      break
    }
  }
  set fmax_mhz 0.0
  if {$wns < 0} {
    set period [expr {2.5 - $wns}]
    set fmax_mhz [expr {1000.0 / $period}]
  } elseif {$wns >= 0} {
    set period [expr {2.5 - $wns}]
    set fmax_mhz [expr {1000.0 / $period}]
  }
  puts $summary "| $strat | done | $wns | $tns | $fep | [format %.1f $fmax_mhz] |"
  close_design
}

close $summary
puts "==> Strategy sweep complete. See results/impl/phase2_strategy_sweep.md"
