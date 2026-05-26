# -----------------------------------------------------------------------------
# render_waveform.tcl
#
# Sourced inside `xsim --gui tb_kvq_top --tclbatch <this>`. The xsim --gui
# session loads the elaborated snapshot, applies wave_config.wcfg via
# open_wave_config, runs the simulation to completion, then exports two PNG
# time-window images.
#
# The testbench $finishes at ~7us (tb_kvq_top.sv:413), so the windows the
# Phase 2.2 spec asked for (0-5us, 50-60us) are scaled proportionally:
#   bringup:    0-2us   (reset deassert, AXI4-Lite contract prog, first req)
#   contention: 4-6us   (T9 TWO_TENANT_PRIORITY_ORDER + T10 EARLIEST_DEADLINE_FIRST)
# -----------------------------------------------------------------------------

set out_dir   [file normalize [file join [pwd] .. .. docs waveforms]]
file mkdir $out_dir
set bringup_png    [file join $out_dir qos_phase1_bringup.png]
set contention_png [file join $out_dir qos_w4_contention.png]

puts "==> Applying wave_config.wcfg"
catch { open_wave_config wave_config.wcfg } err
if {$err ne ""} { puts "INFO: open_wave_config returned: $err" }

puts "==> Running simulation to $finish"
run all

puts "==> Writing $bringup_png  (0us to 2us)"
write_wave_image -force -format png -start_time 0us -end_time 2us $bringup_png

puts "==> Writing $contention_png  (4us to 6us)"
write_wave_image -force -format png -start_time 4us -end_time 6us $contention_png

puts "==> Done."
quit
