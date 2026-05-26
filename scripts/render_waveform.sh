#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# render_waveform.sh
#
# Re-runs the XSim regression to ensure the waveform database is fresh, then
# opens it in batch mode (with start_gui inside the Tcl so write_wave_image
# can render) and exports two PNG windows to docs/waveforms/.
#
# Requires Xvfb at $DISPLAY if no real display is attached - wrap with
# `xvfb-run -a -s "-screen 0 1920x1200x24"`.
# -----------------------------------------------------------------------------
set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJ_ROOT}"
mkdir -p docs/waveforms

XSIM_BIN_DEFAULT="/tools/Xilinx/Vivado/2025.2/bin/xsim"
XSIM_BIN_ALT="/tools/Xilinx/2025.2/Vivado/bin/xsim"
if [ -n "${XSIM_BIN:-}" ] && [ -x "${XSIM_BIN}" ]; then
  :
elif [ -x "${XSIM_BIN_DEFAULT}" ]; then
  XSIM_BIN="${XSIM_BIN_DEFAULT}"
elif [ -x "${XSIM_BIN_ALT}" ]; then
  XSIM_BIN="${XSIM_BIN_ALT}"
elif command -v xsim >/dev/null 2>&1; then
  XSIM_BIN="$(command -v xsim)"
else
  echo "ERROR: xsim not found. Source Vivado settings64.sh or set XSIM_BIN." >&2
  exit 2
fi

# Make sure the .wdb is fresh - the render Tcl wants tb_kvq_top.wdb under
# results/rtl_sim/.
if [ ! -s "results/rtl_sim/tb_kvq_top.wdb" ]; then
  echo "==> WDB missing; running scripts/run_xsim.sh first"
  bash scripts/run_xsim.sh
fi

cp -f sim/xsim/wave_config.wcfg results/rtl_sim/wave_config.wcfg

echo "==> Running ${XSIM_BIN} --gui (under Xvfb) with render_waveform.tcl"
cd results/rtl_sim
# --gui launches the wave window which write_wave_image needs; --tclbatch
# auto-quits at the end of the script. We run the sim live (run all) inside
# the script rather than re-opening the stale .wdb, because open_wave_database
# is a Vivado GUI Tcl command not available in xsim batch.
"${XSIM_BIN}" tb_kvq_top --gui --tclbatch "${PROJ_ROOT}/sim/xsim/render_waveform.tcl"
cd "${PROJ_ROOT}"

echo
echo "==> Outputs:"
ls -la docs/waveforms/ | tail -n +2
