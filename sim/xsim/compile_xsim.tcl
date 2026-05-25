# -----------------------------------------------------------------------------
# compile_xsim.tcl
# Run from project root (not from sim/xsim). Compiles all RTL and testbench
# sources, then elaborates tb_kvq_top. Invoked indirectly by scripts/run_xsim.sh
# via xvlog/xelab; this file is a Tcl wrapper kept for IDE/`xsim -tclbatch` use.
# -----------------------------------------------------------------------------

set proj_root [file normalize [pwd]]
set rtl_dir   [file join $proj_root rtl]
set tb_dir    [file join $proj_root sim tb]

# RTL source order: package first, then leaves, then top
set rtl_files [list \
  [file join $rtl_dir kvq_pkg.sv] \
  [file join $rtl_dir kvq_bram_model.sv] \
  [file join $rtl_dir kvq_token_bucket.sv] \
  [file join $rtl_dir kvq_request_parser.sv] \
  [file join $rtl_dir kvq_tenant_contract_table.sv] \
  [file join $rtl_dir kvq_credit_engine.sv] \
  [file join $rtl_dir kvq_per_tenant_queue_manager.sv] \
  [file join $rtl_dir kvq_deadline_arbiter.sv] \
  [file join $rtl_dir kvq_latency_tracker.sv] \
  [file join $rtl_dir kvq_memory_engine.sv] \
  [file join $rtl_dir kvq_response_builder.sv] \
  [file join $rtl_dir kvq_error_handler.sv] \
  [file join $rtl_dir kvq_sla_monitor.sv] \
  [file join $rtl_dir kvq_perf_counters.sv] \
  [file join $rtl_dir kvq_axil_regs.sv] \
  [file join $rtl_dir kvq_top.sv]
]

set tb_files [list \
  [file join $tb_dir kvq_test_pkg.sv] \
  [file join $tb_dir kvq_assertions.sv] \
  [file join $tb_dir kvq_scoreboard.sv] \
  [file join $tb_dir kvq_traffic_driver.sv] \
  [file join $tb_dir tb_kvq_top.sv]
]

puts "kvq compile: rtl files [llength $rtl_files], tb files [llength $tb_files]"
foreach f [concat $rtl_files $tb_files] { puts "  $f" }
