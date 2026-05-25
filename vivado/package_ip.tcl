# -----------------------------------------------------------------------------
# package_ip.tcl
# Packages kvq_top as a reusable Vivado IP. Interface inference for AXI4-Stream
# and AXI4-Lite is left as a TODO because port naming conventions differ across
# Vivado versions - the inferred interfaces should be reviewed in the GUI
# before publishing. Vendor / library / name / version are baked in.
# -----------------------------------------------------------------------------

set proj_root [file normalize [pwd]]
set ip_dir    [file join $proj_root build ip cxl_kv_forge_qos]
file mkdir $ip_dir

set rtl_dir [file join $proj_root rtl]

ipx::infer_core -vendor shawsilicon.ai -library user -taxonomy /UserIP $rtl_dir
ipx::edit_ip_in_project -upgrade true -name edit_kvq_phase1 -directory $ip_dir [file join $rtl_dir component.xml]

set core [ipx::current_core]
set_property name        "cxl_kv_forge_qos"  $core
set_property display_name "CXL-KV Forge-QoS" $core
set_property description  "Hardware-Enforced SLA Controller for Multi-Tenant LLM KV-Cache Access (Phase 1)" $core
set_property version     "0.1"               $core
set_property vendor      "shawsilicon.ai"    $core
set_property library     "user"              $core
set_property taxonomy    {/UserIP}           $core
set_property supported_families {zynquplus Production} $core

# TODO: infer AXI4-Stream interface s_axis_req
# TODO: infer AXI4-Stream interface m_axis_resp
# TODO: infer AXI4-Lite interface s_axil
# In Vivado GUI: IP Packager > Ports and Interfaces > Auto-Infer Interfaces.
# Vivado >= 2022.x normally handles s_axis_*/m_axis_*/s_axil_* prefixes,
# but the AXIS tlast / AXI4-Lite wstrb signals occasionally need manual mapping.

ipx::create_xgui_files $core
ipx::update_checksums  $core
ipx::save_core         $core
puts "Packaged IP scaffold at $ip_dir. Inspect interface mappings before publishing."
