#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_vivado_synth.sh
#
# Drives the Phase 1 Vivado flow end-to-end:
#   1. create_project.tcl  - creates the project, targets xczu9eg by default
#                            (override with VIVADO_PART for WebPack parts).
#   2. synth_impl_bitstream.tcl - sources create_block_design.tcl, then
#                            runs synth, impl, bitstream.
#
# Artifacts:
#   results/synth/zcu102_synth_util.rpt
#   results/synth/zcu102_timing_summary.rpt
#   results/impl/zcu102_post_route_util.rpt
#   results/impl/zcu102_post_route_timing.rpt
#   results/impl/kvq_top_wrapper.bit
#   results/impl/kvq_top_wrapper.ltx
#   results/synth/synth.log   (full Vivado stdout for both invocations)
# -----------------------------------------------------------------------------
set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIV_DIR="${PROJ_ROOT}/vivado"
SYNTH_DIR="${PROJ_ROOT}/results/synth"
IMPL_DIR="${PROJ_ROOT}/results/impl"
mkdir -p "${SYNTH_DIR}" "${IMPL_DIR}"

if ! command -v vivado >/dev/null 2>&1; then
  echo "ERROR: vivado not found in PATH. Source Vivado settings64.sh and retry." >&2
  exit 2
fi

cd "${PROJ_ROOT}"

LOG="${SYNTH_DIR}/synth.log"
: > "${LOG}"

echo "==> vivado create_project.tcl (part=${VIVADO_PART:-xczu9eg-ffvb1156-2-e})" | tee -a "${LOG}"
vivado -mode batch -nojournal -nolog \
       -source "${VIV_DIR}/create_project.tcl" \
       2>&1 | tee -a "${LOG}"

echo "==> vivado synth_impl_bitstream.tcl (BD-wrapped flow)" | tee -a "${LOG}"
vivado -mode batch -nojournal -nolog \
       -source "${VIV_DIR}/synth_impl_bitstream.tcl" \
       2>&1 | tee -a "${LOG}"

echo "" | tee -a "${LOG}"
echo "==> Artifact check:" | tee -a "${LOG}"
ls -la "${SYNTH_DIR}" "${IMPL_DIR}" 2>&1 | tee -a "${LOG}"
echo "" | tee -a "${LOG}"
echo "Note: timing closure is NOT asserted by this script. Inspect" | tee -a "${LOG}"
echo "      ${IMPL_DIR}/zcu102_post_route_timing.rpt for WNS/TNS." | tee -a "${LOG}"
