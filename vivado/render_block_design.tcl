# -----------------------------------------------------------------------------
# render_block_design.tcl
#
# Export the kvq_phase1_bd block design as PDF and SVG. PNG is produced by
# the shell wrapper (scripts/render_block_design.sh) from the SVG, because
# Vivado 2025.2's write_bd_layout only accepts native / pdf / svg.
# -----------------------------------------------------------------------------

set proj_root [file normalize [pwd]]
set proj_dir  [file join $proj_root build vivado kvq_phase1]
set xpr       [file join $proj_dir kvq_phase1.xpr]
set out_dir   [file join $proj_root docs block_design]
file mkdir $out_dir

if {[file exists $xpr]} {
  puts "==> Re-using existing project: $xpr"
  open_project $xpr
} else {
  puts "==> No project found; rebuilding BD in a fresh project on xczu7ev"
  source [file join $proj_root vivado create_project.tcl]
  source [file join $proj_root vivado create_block_design.tcl]
}

set bd_name "kvq_phase1_bd"
set bd_file [lindex [get_files -quiet ${bd_name}.bd] 0]
if {$bd_file eq ""} {
  puts "ERROR: ${bd_name}.bd not found in project"
  exit 1
}

puts "==> Opening BD: $bd_file"
open_bd_design $bd_file
regenerate_bd_layout
validate_bd_design -quiet

# write_bd_layout uses the GUI canvas; in -mode batch we have to start
# the GUI subsystem manually (Xvfb provides the X display).
start_gui

set pdf_path [file join $out_dir kvq_top_bd.pdf]
set svg_path [file join $out_dir kvq_top_bd.svg]

puts "==> Writing $pdf_path"
write_bd_layout -force -format pdf -orientation landscape $pdf_path

puts "==> Writing $svg_path"
write_bd_layout -force -format svg -orientation landscape $svg_path

stop_gui
close_bd_design [current_bd_design]
puts "==> Done. (PNG is generated from the SVG by the shell wrapper.)"
exit 0
