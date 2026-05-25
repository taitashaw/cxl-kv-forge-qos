# -----------------------------------------------------------------------------
# create_block_design.tcl
#
# Wraps kvq_top inside a Zynq UltraScale+ MPSoC block design:
#   - zynq_ultra_ps_e   (ZCU102 preset; M_AXI_HPM0_LPD + S_AXI_HPx_FPD enabled)
#   - clk_wiz_0         (PL_CLK0 in, 400 MHz out)
#   - reset_0           (proc_sys_reset on the 400 MHz domain)
#   - smartconnect_axil (PS HPM0_LPD -> kvq AXI4-Lite, 1 SI 1 MI 1 clk)
#   - smartconnect_dma_ctrl (PS HPM0_FPD -> axi_dma S_AXI_LITE)
#   - smartconnect_data (axi_dma M_AXI MM2S/S2MM -> PS HP slave)
#   - axi_dma_0         (256-bit AXIS request/response)
#   - kvq_top_0         (kvq_top_bd_wrap, the Phase 1 RTL)
#   - system_ila_0      (debug probes)
#
# kvq_top_0/s_axi_lite is mapped at 0x8000_0000 with 64 KB range.
# -----------------------------------------------------------------------------

set bd_name "kvq_phase1_bd"
puts "==> Creating block design: $bd_name"

set bd_file [get_files -quiet ${bd_name}.bd]
if {$bd_file eq ""} {
  create_bd_design $bd_name
} else {
  open_bd_design $bd_file
}

# -----------------------------------------------------------------------------
# 1. Zynq UltraScale+ PS
# -----------------------------------------------------------------------------
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e ps_e_0]

set part_now [get_property PART [current_project]]
if {[string match "xczu9eg*" $part_now]} {
  puts "==> Applying ZCU102 board preset on PS"
  apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
    $ps
} else {
  puts "==> Skipping ZCU102 preset (part is $part_now); using PS defaults"
  apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} \
    $ps
}

# Enable both master ports (LPD for kvq AXI4-Lite, FPD for axi_dma control)
# and one slave HP port (for axi_dma payload bursts). Force PL_CLK0 to
# 100 MHz exactly so clk_wiz can MMCM-multiply it to 400 MHz.
set_property -dict [list \
  CONFIG.PSU__USE__M_AXI_GP0                {1} \
  CONFIG.PSU__USE__M_AXI_GP2                {1} \
  CONFIG.PSU__USE__S_AXI_GP2                {1} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] $ps

# -----------------------------------------------------------------------------
# 2. Clock wizard - PL_CLK0 -> 400 MHz design clock
# -----------------------------------------------------------------------------
set clkwiz [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_0]
# Match the clk_wiz input frequency to whatever the PS actually produces,
# whether or not the FREQMHZ override above stuck.
connect_bd_net [get_bd_pins $ps/pl_clk0] [get_bd_pins $clkwiz/clk_in1]
set ps_pl_clk_freq_hz [get_property CONFIG.FREQ_HZ [get_bd_pins $ps/pl_clk0]]
set ps_pl_clk_freq_mhz [expr {double($ps_pl_clk_freq_hz) / 1000000.0}]
puts "==> PS pl_clk0 freq: $ps_pl_clk_freq_mhz MHz"
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ                $ps_pl_clk_freq_mhz \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ  {300.000} \
  CONFIG.USE_LOCKED                  {true} \
  CONFIG.USE_RESET                   {true} \
  CONFIG.RESET_PORT                  {resetn} \
  CONFIG.RESET_TYPE                  {ACTIVE_LOW} \
] $clkwiz
connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins $clkwiz/resetn]

# -----------------------------------------------------------------------------
# 3. Processor system reset on the 400 MHz domain
# -----------------------------------------------------------------------------
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset reset_0]
connect_bd_net [get_bd_pins $clkwiz/clk_out1]  [get_bd_pins $rst/slowest_sync_clk]
connect_bd_net [get_bd_pins $ps/pl_resetn0]    [get_bd_pins $rst/ext_reset_in]
connect_bd_net [get_bd_pins $clkwiz/locked]    [get_bd_pins $rst/dcm_locked]

set clk250 [get_bd_pins $clkwiz/clk_out1]
set rstn   [get_bd_pins $rst/peripheral_aresetn]

# -----------------------------------------------------------------------------
# 4. AXI SmartConnect dedicated to the kvq AXI4-Lite path
#    PS M_AXI_HPM0_LPD -> smartconnect_axil -> kvq_top_0/s_axi_lite
# -----------------------------------------------------------------------------
set sc_axil [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smartconnect_axil]
set_property -dict [list \
  CONFIG.NUM_SI {1} \
  CONFIG.NUM_MI {1} \
  CONFIG.NUM_CLKS {1} \
] $sc_axil
connect_bd_net $clk250 [get_bd_pins $sc_axil/aclk]
connect_bd_net $rstn   [get_bd_pins $sc_axil/aresetn]
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM0_LPD] [get_bd_intf_pins $sc_axil/S00_AXI]
connect_bd_net $clk250 [get_bd_pins $ps/maxihpm0_lpd_aclk]

# -----------------------------------------------------------------------------
# 5. AXI SmartConnect for DMA register access (PS HPM0_FPD -> axi_dma)
# -----------------------------------------------------------------------------
set sc_dma_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smartconnect_dma_ctrl]
set_property -dict [list \
  CONFIG.NUM_SI {1} \
  CONFIG.NUM_MI {1} \
  CONFIG.NUM_CLKS {1} \
] $sc_dma_ctrl
connect_bd_net $clk250 [get_bd_pins $sc_dma_ctrl/aclk]
connect_bd_net $rstn   [get_bd_pins $sc_dma_ctrl/aresetn]
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM0_FPD] [get_bd_intf_pins $sc_dma_ctrl/S00_AXI]
connect_bd_net $clk250 [get_bd_pins $ps/maxihpm0_fpd_aclk]

# -----------------------------------------------------------------------------
# 6. AXI SmartConnect for the DMA data plane (DMA -> PS HP slave)
# -----------------------------------------------------------------------------
set sc_data [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smartconnect_data]
set_property -dict [list \
  CONFIG.NUM_SI {2} \
  CONFIG.NUM_MI {1} \
  CONFIG.NUM_CLKS {1} \
] $sc_data
connect_bd_net $clk250 [get_bd_pins $sc_data/aclk]
connect_bd_net $rstn   [get_bd_pins $sc_data/aresetn]

# -----------------------------------------------------------------------------
# 7. AXI DMA - drives s_axis_req, sinks m_axis_resp
# -----------------------------------------------------------------------------
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_0]
set_property -dict [list \
  CONFIG.c_include_sg              {0} \
  CONFIG.c_sg_length_width         {26} \
  CONFIG.c_m_axis_mm2s_tdata_width {256} \
  CONFIG.c_s_axis_s2mm_tdata_width {256} \
  CONFIG.c_mm2s_burst_size         {8} \
  CONFIG.c_s2mm_burst_size         {8} \
] $dma
connect_bd_intf_net [get_bd_intf_pins $sc_dma_ctrl/M00_AXI] [get_bd_intf_pins $dma/S_AXI_LITE]
connect_bd_net $clk250 [get_bd_pins $dma/s_axi_lite_aclk]
connect_bd_net $clk250 [get_bd_pins $dma/m_axi_mm2s_aclk]
connect_bd_net $clk250 [get_bd_pins $dma/m_axi_s2mm_aclk]
connect_bd_net $rstn   [get_bd_pins $dma/axi_resetn]

# DMA payload paths into the data smartconnect
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_MM2S] [get_bd_intf_pins $sc_data/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_S2MM] [get_bd_intf_pins $sc_data/S01_AXI]

# Discover the PS slave port name dynamically.
set ps_slave ""
foreach candidate {S_AXI_HPC0_FPD S_AXI_HP0_FPD S_AXI_HP1_FPD S_AXI_HPC1_FPD} {
  if {[llength [get_bd_intf_pins -quiet $ps/$candidate]] > 0} {
    set ps_slave $ps/$candidate
    break
  }
}
if {$ps_slave eq ""} {
  puts "ERROR: no PS slave AXI port available on $ps"
  exit 1
}
puts "==> Using PS slave port: $ps_slave"
connect_bd_intf_net [get_bd_intf_pins $sc_data/M00_AXI] [get_bd_intf_pins $ps_slave]
set slave_short [string tolower [string map {S_AXI_ saxi _FPD _fpd} [file tail $ps_slave]]]
set ps_slave_aclk [get_bd_pins -quiet $ps/${slave_short}_aclk]
if {$ps_slave_aclk ne ""} { connect_bd_net $clk250 $ps_slave_aclk }

# -----------------------------------------------------------------------------
# 8. kvq_top_0 (Verilog wrapper around the SV kvq_top)
# -----------------------------------------------------------------------------
set kvq [create_bd_cell -type module -reference kvq_top_bd_wrap kvq_top_0]
connect_bd_net $clk250 [get_bd_pins $kvq/clk]
connect_bd_net $rstn   [get_bd_pins $kvq/rst_n]

# Connect the AXI4-Lite path: smartconnect_axil/M00 -> kvq/s_axi_lite
set kvq_axil_iface [get_bd_intf_pins -quiet $kvq/s_axi_lite]
if {$kvq_axil_iface eq ""} {
  puts "ERROR: kvq_top s_axi_lite interface not auto-inferred. Cannot wire AXIL."
  exit 1
}
puts "==> kvq AXI4-Lite interface: $kvq_axil_iface"
connect_bd_intf_net [get_bd_intf_pins $sc_axil/M00_AXI] $kvq_axil_iface

# Connect AXI4-Stream paths
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXIS_MM2S] [get_bd_intf_pins $kvq/s_axis_req]
connect_bd_intf_net [get_bd_intf_pins $kvq/m_axis_resp] [get_bd_intf_pins $dma/S_AXIS_S2MM]

# -----------------------------------------------------------------------------
# 9. Debug probes
#
# Internal kvq_top debug nets are tagged MARK_DEBUG in RTL. Vivado's
# synthesis preserves them and the impl flow auto-inserts a Debug Hub
# plus an ILA via the post-synth Tcl step in synth_impl_bitstream.tcl.
# Doing this in the netlist (rather than via system_ila in the BD)
# sidesteps BD 41-759 / 41-2383 critical warnings caused by attempting
# to probe pins that are part of an IPI-inferred AXIS bus interface.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 10. Address map
# -----------------------------------------------------------------------------
# Auto-assign everything first, then move the kvq AXI4-Lite slot to the
# explicit 0x8000_0000 / 64 KB window the user-facing memory map expects.
assign_bd_address

set kvq_seg [get_bd_addr_segs -quiet "*kvq_top_0/*"]
if {[llength $kvq_seg] == 0} {
  puts "WARN: kvq_top_0 address segment not found; cannot apply 0x80000000 / 64K base"
} else {
  puts "==> Relocating kvq AXI4-Lite to 0x80000000 / 64K ($kvq_seg)"
  set ps_addr_space [get_bd_addr_spaces $ps/Data]
  exclude_bd_addr_seg -target_address_space $ps_addr_space $kvq_seg
  assign_bd_address -target_address_space $ps_addr_space \
                    -offset 0x80000000 -range 64K $kvq_seg
}

# -----------------------------------------------------------------------------
# 11. Validate
# -----------------------------------------------------------------------------
puts "==> Validating block design"
validate_bd_design

save_bd_design

# Generate the HDL wrapper around the BD and add it to the project as top
set bd_file [get_files ${bd_name}.bd]
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper
update_compile_order -fileset sources_1
set_property top ${bd_name}_wrapper [current_fileset]

puts "==> Block design $bd_name generated. Wrapper top: ${bd_name}_wrapper"
