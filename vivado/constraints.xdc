# -----------------------------------------------------------------------------
# constraints.xdc
#
# The Phase 1 BD-wrapped flow gets all of its clocking and IO constraints
# from the IP cores in the block design (zynq_ultra_ps_e, clk_wiz,
# axi_dma). PL pin assignments come from the ZCU102 board files when the
# board preset is applied.
#
# Design clock target: 400 MHz (2.500 ns period). The clock itself is
# created by clk_wiz_0 inside the BD; this file does not re-create that
# clock - keeping it here for reference and for the standalone kvq_top
# flow (no BD) where the user assigns clk to a physical pin.
#
# For the standalone path, an external create_clock would look like:
#   create_clock -name kvq_clk -period 2.500 [get_ports clk]
#   set_input_delay  -clock kvq_clk -max 1.000 [get_ports s_axis_req_*]
#   set_output_delay -clock kvq_clk -max 1.000 [get_ports m_axis_resp_*]
#
# Debug-core constraints (create_debug_core / connect_debug_port) are
# emitted by synth_impl_bitstream.tcl after synthesis - DO NOT save them
# back into this XDC because the post-synth net names depend on the
# specific synth run, and stale entries here will fail next time.
# -----------------------------------------------------------------------------
