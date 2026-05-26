# Quick post-build debug-core insertion + .ltx generation.
# Opens the winning impl run, creates an ILA on MARK_DEBUG nets, writes
# kvq_top_wrapper.ltx alongside the bitstream.

set proj_root [file normalize [pwd]]
set proj_dir  [file join $proj_root build vivado kvq_phase1]
set xpr       [file join $proj_dir kvq_phase1.xpr]
set impl_dir  [file join $proj_root results impl]

open_project $xpr
open_run impl_Performance_NetDelay_high

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
  puts "==> ILA clock: $ila_clk"
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
  write_debug_probes -force [file join $impl_dir kvq_top_wrapper.ltx]
}
exit
