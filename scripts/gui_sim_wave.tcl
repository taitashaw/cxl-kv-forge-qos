# ============================================================
# CXL-KV Forge-QoS — GUI sim + waveform PNG export
# Run from project root:  vivado -mode gui -source scripts/gui_sim_wave.tcl
# ============================================================

set PROJ_ROOT [file normalize "."]
set XPR       "$PROJ_ROOT/build/vivado/kvq_phase1/kvq_phase1.xpr"
set WAVE_CFG  "$PROJ_ROOT/sim/xsim/wave_config.wcfg"
set OUT_DIR   "$PROJ_ROOT/docs/waveforms"

file mkdir $OUT_DIR

if {![file exists $XPR]} {
    puts stderr "ERROR: project not found at $XPR"
    puts stderr "Run scripts/run_vivado_synth.sh first to create the project."
    return
}

if {![file exists $WAVE_CFG]} {
    puts stderr "ERROR: wave config not found at $WAVE_CFG"
    return
}

open_project $XPR

# Point the sim fileset at the testbench top
set_property top tb_kvq_top      [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Launch behavioral sim (Wave window opens automatically in GUI mode)
launch_simulation -mode behavioral

# Replace the default wave view with the 42-signal audited config
open_wave_config $WAVE_CFG

# Run long enough to cover both bring-up and contention windows
restart
run 6 us

# Export the two windows as PNGs
write_wave_image -force -format png \
    -start_time 0us -end_time 2us \
    "$OUT_DIR/qos_phase1_bringup.png"
puts "==> Wrote $OUT_DIR/qos_phase1_bringup.png  (0-2us bring-up)"

write_wave_image -force -format png \
    -start_time 4us -end_time 6us \
    "$OUT_DIR/qos_w4_contention.png"
puts "==> Wrote $OUT_DIR/qos_w4_contention.png  (4-6us contention)"

puts ""
puts "============================================================"
puts "Waveforms exported. Wave window stays open for interactive inspection."
puts "Use Vivado menus: View > Scopes / Objects to add more signals if needed."
puts "============================================================"
