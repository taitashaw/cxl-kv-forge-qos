# -----------------------------------------------------------------------------
# key_signals.tcl
#
# Focused XSim wave view containing only the signals that demonstrate the
# Phase 1 architectural claims:
#   - AXIS request/response handshake on the host interface
#   - AXI4-Lite contract programming
#   - Deadline arbiter pulses + winner slack/priority + per-tenant eligibility
#   - Credit-snapshot + starvation pulses
#   - Per-tenant queue occupancy
#   - SLA counters and overall pass/fail counters from the testbench
#
# Path conventions used here:
#   /tb_kvq_top/...           - testbench ports/signals
#   /tb_kvq_top/u_dut/...     - kvq_top inter-module wires at the top of DUT
#   /tb_kvq_top/u_dut/u_arb/  - signals scoped inside the deadline arbiter
#   /tb_kvq_top/u_dut/u_credit/ - signals scoped inside the credit engine
#   /tb_kvq_top/u_dut/u_qmgr/ - signals scoped inside the queue manager
#
# Two ways to use this:
#   (1) From an open xsim GUI session:
#         source sim/xsim/key_signals.tcl
#   (2) At launch (parses cleanly even without DISPLAY):
#         cd results/rtl_sim
#         xsim tb_kvq_top --gui --tclbatch ../../sim/xsim/key_signals.tcl
#
# Do NOT call `run all` more than once - tb_kvq_top.sv:413 calls $finish
# at ~7038 ns, so subsequent run-all invocations only toggle clocks into
# post-finish idle (counters appear flat after that point).
# -----------------------------------------------------------------------------

# Clean slate (no-op the first time)
catch { remove_wave -of_objects [get_waves *] }

# Create groups first (XSim Tcl: add_wave_group, then add_wave -into <group>)
add_wave_group time
add_wave_group host_axis
add_wave_group axil_program
add_wave_group arbitration
add_wave_group credits
add_wave_group queues
add_wave_group sla
add_wave_group tb_status

# ---- time -------------------------------------------------------------------
add_wave -into time /tb_kvq_top/clk
add_wave -into time /tb_kvq_top/rst_n
add_wave -into time /tb_kvq_top/u_dut/cycle_counter

# ---- host_axis --------------------------------------------------------------
add_wave -into host_axis /tb_kvq_top/s_axis_req_tvalid
add_wave -into host_axis /tb_kvq_top/s_axis_req_tready
add_wave -into host_axis /tb_kvq_top/s_axis_req_tdata
add_wave -into host_axis /tb_kvq_top/m_axis_resp_tvalid
add_wave -into host_axis /tb_kvq_top/m_axis_resp_tready
add_wave -into host_axis /tb_kvq_top/m_axis_resp_tdata

# ---- axil_program -----------------------------------------------------------
add_wave -into axil_program /tb_kvq_top/s_axil_awvalid
add_wave -into axil_program /tb_kvq_top/s_axil_wdata
add_wave -into axil_program /tb_kvq_top/u_dut/cfg_write
add_wave -into axil_program /tb_kvq_top/u_dut/cfg_tenant_idx
add_wave -into axil_program /tb_kvq_top/u_dut/cfg_field_sel

# ---- arbitration ------------------------------------------------------------
add_wave -into arbitration /tb_kvq_top/u_dut/qm_deq_valid
add_wave -into arbitration /tb_kvq_top/u_dut/u_arb/sel_valid
add_wave -into arbitration /tb_kvq_top/u_dut/u_arb/sel_tenant_idx
add_wave -into arbitration /tb_kvq_top/u_dut/u_arb/deq_grant
add_wave -into arbitration /tb_kvq_top/u_dut/u_arb/best_slack
add_wave -into arbitration /tb_kvq_top/u_dut/u_arb/best_prio

# ---- credits ----------------------------------------------------------------
add_wave -into credits /tb_kvq_top/u_dut/u_credit/credit_snapshot
add_wave -into credits /tb_kvq_top/u_dut/u_credit/credit_starvation_pulse

# ---- queues -----------------------------------------------------------------
add_wave -into queues /tb_kvq_top/u_dut/per_tenant_occ[0]
add_wave -into queues /tb_kvq_top/u_dut/per_tenant_occ[1]
add_wave -into queues /tb_kvq_top/u_dut/per_tenant_occ[2]
add_wave -into queues /tb_kvq_top/u_dut/per_tenant_occ[3]
add_wave -into queues /tb_kvq_top/u_dut/per_tenant_occ[4]
add_wave -into queues /tb_kvq_top/u_dut/per_tenant_occ[5]
add_wave -into queues /tb_kvq_top/u_dut/per_tenant_occ[6]
add_wave -into queues /tb_kvq_top/u_dut/per_tenant_occ[7]
add_wave -into queues /tb_kvq_top/global_queue_occupancy
add_wave -into queues /tb_kvq_top/queue_full

# ---- sla --------------------------------------------------------------------
add_wave -into sla /tb_kvq_top/deadline_miss_seen
add_wave -into sla /tb_kvq_top/error_seen
add_wave -into sla /tb_kvq_top/u_dut/cnt_deadline_miss
add_wave -into sla /tb_kvq_top/u_dut/cnt_credit_starvation

# ---- tb_status --------------------------------------------------------------
add_wave -into tb_status /tb_kvq_top/n_pass
add_wave -into tb_status /tb_kvq_top/n_fail

# zoom_fit is GUI-only; swallow the error in batch use so the script can be
# parse-verified with -tclbatch without a DISPLAY.
catch { zoom_fit }
