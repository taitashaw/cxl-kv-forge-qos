#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_xsim.sh
# Phase 1 XSim driver. Compiles all RTL and TB sources via xvlog, elaborates
# tb_kvq_top with xelab, then runs the simulation via xsim. All artifacts land
# under results/rtl_sim/.
#
# Requires: Xilinx Vivado / XSim in PATH (xvlog, xelab, xsim).
# -----------------------------------------------------------------------------
set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTL_DIR="${PROJ_ROOT}/rtl"
TB_DIR="${PROJ_ROOT}/sim/tb"
XSIM_DIR="${PROJ_ROOT}/sim/xsim"
RESULTS_DIR="${PROJ_ROOT}/results/rtl_sim"

mkdir -p "${RESULTS_DIR}"
cd "${RESULTS_DIR}"

# RTL sources in dependency order
RTL_FILES=(
  "${RTL_DIR}/kvq_pkg.sv"
  "${RTL_DIR}/kvq_bram_model.sv"
  "${RTL_DIR}/kvq_token_bucket.sv"
  "${RTL_DIR}/kvq_request_parser.sv"
  "${RTL_DIR}/kvq_tenant_contract_table.sv"
  "${RTL_DIR}/kvq_credit_engine.sv"
  "${RTL_DIR}/kvq_per_tenant_queue_manager.sv"
  "${RTL_DIR}/kvq_deadline_arbiter.sv"
  "${RTL_DIR}/kvq_latency_tracker.sv"
  "${RTL_DIR}/kvq_memory_engine.sv"
  "${RTL_DIR}/kvq_response_builder.sv"
  "${RTL_DIR}/kvq_error_handler.sv"
  "${RTL_DIR}/kvq_sla_monitor.sv"
  "${RTL_DIR}/kvq_perf_counters.sv"
  "${RTL_DIR}/kvq_axil_regs.sv"
  "${RTL_DIR}/kvq_top.sv"
)

TB_FILES=(
  "${TB_DIR}/kvq_test_pkg.sv"
  "${TB_DIR}/kvq_assertions.sv"
  "${TB_DIR}/kvq_scoreboard.sv"
  "${TB_DIR}/kvq_traffic_driver.sv"
  "${TB_DIR}/tb_kvq_top.sv"
)

if ! command -v xvlog >/dev/null 2>&1; then
  echo "ERROR: xvlog not found in PATH. Source Vivado settings64.sh and retry." >&2
  exit 2
fi

echo "==> xvlog (compile)"
xvlog -sv \
  --include "${RTL_DIR}" \
  --include "${TB_DIR}" \
  "${RTL_FILES[@]}" "${TB_FILES[@]}" 2>&1 | tee xsim_compile.log

echo "==> xelab (elaborate)"
# Snapshot name == tb top so the resulting .wdb is tb_kvq_top.wdb (the path
# the Sprint Y wave config and docs expect).
xelab -debug typical -L work tb_kvq_top -snapshot tb_kvq_top 2>&1 | tee xsim_elab.log

echo "==> xsim (run)"
xsim tb_kvq_top --runall --tclbatch "${XSIM_DIR}/run_xsim.tcl" --wdb tb_kvq_top.wdb 2>&1 | tee xsim.log

# Pass/fail determination
if grep -q "RESULT: PASS" xsim.log; then
  echo "Phase 1 XSim: PASS"
  exit 0
elif grep -q "RESULT: FAIL" xsim.log; then
  echo "Phase 1 XSim: FAIL"
  exit 1
else
  echo "Phase 1 XSim: UNKNOWN (no RESULT line found)"
  exit 3
fi
