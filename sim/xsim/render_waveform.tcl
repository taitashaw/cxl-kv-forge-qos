# -----------------------------------------------------------------------------
# render_waveform.tcl
# Sourced inside `xsim --gui tb_kvq_top --tclbatch <this>` from any CWD.
# Loads wave_config.wcfg, runs sim to $finish (~7.14us), exports two PNGs.
# -----------------------------------------------------------------------------

set script_dir [file normalize [file dirname [info script]]]
set proj_root  [file normalize [file join $script_dir .. ..]]
set wcfg_path  [file join $script_dir wave_config.wcfg]
set out_dir    [file join $proj_root docs waveforms]

file mkdir $out_dir
set bringup_png    [file join $out_dir qos_phase1_bringup.png]
set contention_png [file join $out_dir qos_w4_contention.png]

puts "==> Applying $wcfg_path"
catch { open_wave_config $wcfg_path } err
if {$err ne ""} { puts "INFO: open_wave_config returned: $err" }

# Belt-and-braces: log everything before running, in case wcfg doesn't auto-log
catch { log_wave -recursive / }

puts {==> Running simulation to $finish}
run all

puts "==> Writing $bringup_png  (0us to 2us)"
write_wave_image -force -format png -start_time 0us -end_time 2us $bringup_png

puts "==> Writing $contention_png  (4us to 6us)"
write_wave_image -force -format png -start_time 4us -end_time 6us $contention_png

puts "==> Done."
quit
