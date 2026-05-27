# ============================================================
# CXL-KV Forge-QoS — GUI block design open + multi-format export
# Run from project root:  vivado -mode gui -source scripts/gui_bd_export.tcl
# ============================================================

set PROJ_ROOT [file normalize "."]
set XPR       "$PROJ_ROOT/build/vivado/kvq_phase1/kvq_phase1.xpr"
set OUT_DIR   "$PROJ_ROOT/docs/block_design"

file mkdir $OUT_DIR

if {![file exists $XPR]} {
    puts stderr "ERROR: project not found at $XPR"
    puts stderr "Run scripts/run_vivado_synth.sh first to create the project."
    return
}

open_project $XPR

set bd_files [get_files -filter {FILE_TYPE == "Block Designs"}]
if {[llength $bd_files] == 0} {
    puts stderr "ERROR: no .bd files in project"
    return
}

foreach bd $bd_files {
    set bd_name [file rootname [file tail $bd]]
    puts "==> Opening block design: $bd_name"

    open_bd_design $bd
    regenerate_bd_layout
    validate_bd_design
    save_bd_design

    set png "$OUT_DIR/${bd_name}.png"
    set pdf "$OUT_DIR/${bd_name}.pdf"
    set svg "$OUT_DIR/${bd_name}.svg"

    write_bd_layout -force -format png -orientation landscape -file $png
    write_bd_layout -force -format pdf -orientation landscape -file $pdf
    write_bd_layout -force -format svg -orientation landscape -file $svg

    puts "  ==> $png"
    puts "  ==> $pdf"
    puts "  ==> $svg"
}

puts ""
puts "============================================================"
puts "Block design exported. IP Integrator stays open. Press F8 to zoom fit."
puts "============================================================"
