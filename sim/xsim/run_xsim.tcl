# -----------------------------------------------------------------------------
# run_xsim.tcl
# Tcl entry point invoked by `xsim --tclbatch run_xsim.tcl tb_kvq_top`. Opens
# the waveform database, logs all signals, runs simulation to completion, and
# closes cleanly.
# -----------------------------------------------------------------------------

log_wave -recursive /
run -all
quit
