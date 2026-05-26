#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# render_block_design.sh
#
# Export the kvq_phase1_bd block design as PNG + PDF under docs/block_design/.
# Reuses an existing project at build/vivado/kvq_phase1/ if present; otherwise
# the Tcl rebuilds the BD in a fresh in-memory project on xczu7ev.
# -----------------------------------------------------------------------------
set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJ_ROOT}"
mkdir -p docs/block_design

# Try the canonical path first, then fall back to whatever vivado is on PATH.
DEFAULT_BIN="/tools/Xilinx/Vivado/2025.2/bin/vivado"
ALT_BIN="/tools/Xilinx/2025.2/Vivado/bin/vivado"
if [ -n "${VIVADO_BIN:-}" ] && [ -x "${VIVADO_BIN}" ]; then
  :
elif [ -x "${DEFAULT_BIN}" ]; then
  VIVADO_BIN="${DEFAULT_BIN}"
elif [ -x "${ALT_BIN}" ]; then
  VIVADO_BIN="${ALT_BIN}"
elif command -v vivado >/dev/null 2>&1; then
  VIVADO_BIN="$(command -v vivado)"
else
  echo "ERROR: vivado not found. Set VIVADO_BIN or source settings64.sh." >&2
  exit 2
fi

echo "==> Using Vivado: ${VIVADO_BIN}"
"${VIVADO_BIN}" -mode batch -nojournal -nolog \
                -source vivado/render_block_design.tcl

# Vivado 2025.2's write_bd_layout only emits native / pdf / svg.
# pdftocairo from poppler-utils renders the PDF cleanly (fonts intact);
# ImageMagick's convert is a fallback that drops most text.
PDF="docs/block_design/kvq_top_bd.pdf"
SVG="docs/block_design/kvq_top_bd.svg"
PNG="docs/block_design/kvq_top_bd.png"
if [ -f "${PDF}" ] && command -v pdftocairo >/dev/null 2>&1; then
  echo "==> PDF -> PNG via pdftocairo"
  pdftocairo -png -r 150 -singlefile "${PDF}" "${PNG%.png}"
elif [ -f "${SVG}" ] && command -v rsvg-convert >/dev/null 2>&1; then
  echo "==> SVG -> PNG via rsvg-convert"
  rsvg-convert -d 150 -p 150 -o "${PNG}" "${SVG}"
elif [ -f "${SVG}" ] && command -v inkscape >/dev/null 2>&1; then
  echo "==> SVG -> PNG via inkscape"
  inkscape -d 150 -o "${PNG}" "${SVG}"
elif [ -f "${SVG}" ] && command -v convert >/dev/null 2>&1; then
  echo "==> SVG -> PNG via ImageMagick convert (text rendering may be poor)"
  convert -density 150 "${SVG}" "${PNG}"
else
  echo "WARN: no PDF/SVG -> PNG converter found." >&2
  echo "      Install poppler-utils (pdftocairo) or librsvg2-bin." >&2
fi

echo
echo "==> Outputs:"
ls -la docs/block_design/ | tail -n +2
