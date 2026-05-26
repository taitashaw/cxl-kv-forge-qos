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

create_debug_core u_ila_dbg ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_dbg]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_dbg]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_dbg]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_dbg]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_dbg]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_dbg]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_dbg]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_dbg]
set_property port_width 1 [get_debug_ports u_ila_dbg/clk]
connect_debug_port u_ila_dbg/clk [get_nets [list kvq_phase1_bd_i/kvq_top_0/clk]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe0]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe0]
connect_debug_port u_ila_dbg/probe0 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_arb_sel_tenant_idx[0]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe1]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe1]
connect_debug_port u_ila_dbg/probe1 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_arb_sel_tenant_idx[1]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe2]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe2]
connect_debug_port u_ila_dbg/probe2 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_arb_sel_tenant_idx[2]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe3]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe3]
connect_debug_port u_ila_dbg/probe3 [get_nets [list kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_arb_sel_valid]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe4]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe4]
connect_debug_port u_ila_dbg/probe4 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[0]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe5]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe5]
connect_debug_port u_ila_dbg/probe5 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[10]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe6]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe6]
connect_debug_port u_ila_dbg/probe6 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[11]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe7]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe7]
connect_debug_port u_ila_dbg/probe7 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[12]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe8]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe8]
connect_debug_port u_ila_dbg/probe8 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[13]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe9]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe9]
connect_debug_port u_ila_dbg/probe9 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[14]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe10]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe10]
connect_debug_port u_ila_dbg/probe10 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[15]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe11]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe11]
connect_debug_port u_ila_dbg/probe11 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[16]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe12]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe12]
connect_debug_port u_ila_dbg/probe12 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[17]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe13]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe13]
connect_debug_port u_ila_dbg/probe13 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[18]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe14]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe14]
connect_debug_port u_ila_dbg/probe14 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[19]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe15]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe15]
connect_debug_port u_ila_dbg/probe15 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[1]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe16]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe16]
connect_debug_port u_ila_dbg/probe16 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[20]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe17]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe17]
connect_debug_port u_ila_dbg/probe17 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[21]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe18]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe18]
connect_debug_port u_ila_dbg/probe18 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[22]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe19]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe19]
connect_debug_port u_ila_dbg/probe19 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[23]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe20]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe20]
connect_debug_port u_ila_dbg/probe20 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[24]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe21]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe21]
connect_debug_port u_ila_dbg/probe21 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[25]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe22]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe22]
connect_debug_port u_ila_dbg/probe22 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[26]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe23]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe23]
connect_debug_port u_ila_dbg/probe23 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[27]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe24]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe24]
connect_debug_port u_ila_dbg/probe24 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[28]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe25]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe25]
connect_debug_port u_ila_dbg/probe25 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[29]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe26]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe26]
connect_debug_port u_ila_dbg/probe26 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[2]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe27]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe27]
connect_debug_port u_ila_dbg/probe27 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[30]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe28]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe28]
connect_debug_port u_ila_dbg/probe28 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[31]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe29]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe29]
connect_debug_port u_ila_dbg/probe29 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[3]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe30]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe30]
connect_debug_port u_ila_dbg/probe30 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[4]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe31]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe31]
connect_debug_port u_ila_dbg/probe31 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[5]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe32]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe32]
connect_debug_port u_ila_dbg/probe32 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[6]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe33]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe33]
connect_debug_port u_ila_dbg/probe33 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[7]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe34]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe34]
connect_debug_port u_ila_dbg/probe34 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[8]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe35]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe35]
connect_debug_port u_ila_dbg/probe35 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_snapshot[9]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe36]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe36]
connect_debug_port u_ila_dbg/probe36 [get_nets [list kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_credit_starvation_pulse]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe37]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe37]
connect_debug_port u_ila_dbg/probe37 [get_nets [list kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_deadline_miss]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe38]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe38]
connect_debug_port u_ila_dbg/probe38 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[0]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe39]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe39]
connect_debug_port u_ila_dbg/probe39 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[10]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe40]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe40]
connect_debug_port u_ila_dbg/probe40 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[11]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe41]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe41]
connect_debug_port u_ila_dbg/probe41 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[12]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe42]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe42]
connect_debug_port u_ila_dbg/probe42 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[13]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe43]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe43]
connect_debug_port u_ila_dbg/probe43 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[14]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe44]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe44]
connect_debug_port u_ila_dbg/probe44 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[15]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe45]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe45]
connect_debug_port u_ila_dbg/probe45 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[16]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe46]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe46]
connect_debug_port u_ila_dbg/probe46 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[17]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe47]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe47]
connect_debug_port u_ila_dbg/probe47 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[18]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe48]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe48]
connect_debug_port u_ila_dbg/probe48 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[19]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe49]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe49]
connect_debug_port u_ila_dbg/probe49 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[1]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe50]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe50]
connect_debug_port u_ila_dbg/probe50 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[20]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe51]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe51]
connect_debug_port u_ila_dbg/probe51 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[21]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe52]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe52]
connect_debug_port u_ila_dbg/probe52 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[22]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe53]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe53]
connect_debug_port u_ila_dbg/probe53 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[23]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe54]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe54]
connect_debug_port u_ila_dbg/probe54 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[24]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe55]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe55]
connect_debug_port u_ila_dbg/probe55 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[25]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe56]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe56]
connect_debug_port u_ila_dbg/probe56 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[26]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe57]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe57]
connect_debug_port u_ila_dbg/probe57 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[27]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe58]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe58]
connect_debug_port u_ila_dbg/probe58 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[28]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe59]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe59]
connect_debug_port u_ila_dbg/probe59 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[29]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe60]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe60]
connect_debug_port u_ila_dbg/probe60 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[2]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe61]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe61]
connect_debug_port u_ila_dbg/probe61 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[30]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe62]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe62]
connect_debug_port u_ila_dbg/probe62 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[31]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe63]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe63]
connect_debug_port u_ila_dbg/probe63 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[3]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe64]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe64]
connect_debug_port u_ila_dbg/probe64 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[4]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe65]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe65]
connect_debug_port u_ila_dbg/probe65 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[5]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe66]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe66]
connect_debug_port u_ila_dbg/probe66 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[6]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe67]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe67]
connect_debug_port u_ila_dbg/probe67 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[7]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe68]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe68]
connect_debug_port u_ila_dbg/probe68 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[8]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe69]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe69]
connect_debug_port u_ila_dbg/probe69 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_latency_cycles[9]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe70]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe70]
connect_debug_port u_ila_dbg/probe70 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[0]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe71]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe71]
connect_debug_port u_ila_dbg/probe71 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[10]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe72]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe72]
connect_debug_port u_ila_dbg/probe72 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[11]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe73]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe73]
connect_debug_port u_ila_dbg/probe73 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[12]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe74]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe74]
connect_debug_port u_ila_dbg/probe74 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[13]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe75]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe75]
connect_debug_port u_ila_dbg/probe75 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[14]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe76]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe76]
connect_debug_port u_ila_dbg/probe76 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[15]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe77]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe77]
connect_debug_port u_ila_dbg/probe77 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[16]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe78]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe78]
connect_debug_port u_ila_dbg/probe78 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[17]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe79]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe79]
connect_debug_port u_ila_dbg/probe79 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[18]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe80]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe80]
connect_debug_port u_ila_dbg/probe80 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[19]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe81]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe81]
connect_debug_port u_ila_dbg/probe81 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[1]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe82]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe82]
connect_debug_port u_ila_dbg/probe82 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[20]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe83]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe83]
connect_debug_port u_ila_dbg/probe83 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[21]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe84]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe84]
connect_debug_port u_ila_dbg/probe84 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[22]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe85]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe85]
connect_debug_port u_ila_dbg/probe85 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[23]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe86]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe86]
connect_debug_port u_ila_dbg/probe86 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[24]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe87]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe87]
connect_debug_port u_ila_dbg/probe87 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[25]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe88]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe88]
connect_debug_port u_ila_dbg/probe88 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[26]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe89]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe89]
connect_debug_port u_ila_dbg/probe89 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[27]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe90]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe90]
connect_debug_port u_ila_dbg/probe90 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[28]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe91]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe91]
connect_debug_port u_ila_dbg/probe91 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[29]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe92]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe92]
connect_debug_port u_ila_dbg/probe92 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[2]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe93]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe93]
connect_debug_port u_ila_dbg/probe93 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[30]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe94]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe94]
connect_debug_port u_ila_dbg/probe94 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[31]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe95]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe95]
connect_debug_port u_ila_dbg/probe95 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[32]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe96]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe96]
connect_debug_port u_ila_dbg/probe96 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[33]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe97]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe97]
connect_debug_port u_ila_dbg/probe97 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[34]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe98]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe98]
connect_debug_port u_ila_dbg/probe98 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[35]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe99]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe99]
connect_debug_port u_ila_dbg/probe99 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[36]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe100]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe100]
connect_debug_port u_ila_dbg/probe100 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[37]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe101]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe101]
connect_debug_port u_ila_dbg/probe101 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[38]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe102]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe102]
connect_debug_port u_ila_dbg/probe102 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[39]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe103]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe103]
connect_debug_port u_ila_dbg/probe103 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[3]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe104]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe104]
connect_debug_port u_ila_dbg/probe104 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[4]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe105]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe105]
connect_debug_port u_ila_dbg/probe105 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[5]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe106]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe106]
connect_debug_port u_ila_dbg/probe106 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[6]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe107]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe107]
connect_debug_port u_ila_dbg/probe107 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[7]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe108]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe108]
connect_debug_port u_ila_dbg/probe108 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[8]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe109]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe109]
connect_debug_port u_ila_dbg/probe109 [get_nets [list {kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_per_tenant_occupancy_flat[9]}]]
create_debug_port u_ila_dbg probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_dbg/probe110]
set_property port_width 1 [get_debug_ports u_ila_dbg/probe110]
connect_debug_port u_ila_dbg/probe110 [get_nets [list kvq_phase1_bd_i/kvq_top_0/inst/u_kvq_top/dbg_refill_pulse]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets u_ila_dbg_clk]
