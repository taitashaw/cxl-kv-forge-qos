// -----------------------------------------------------------------------------
// kvq_latency_tracker.sv
// Tags accepted requests with the current value of a free-running 32-bit cycle
// counter. On the response path the tag is subtracted from the current counter
// to produce latency_cycles, and compared against req.deadline_cycles to
// produce deadline_miss.
//
// MVP simplification: latency_tracker is a thin pass-through wrapper that
// attaches the timestamp to the request as it leaves the arbiter, and
// computes the latency at the response builder side. To keep ports clean, we
// expose a separate timestamp output and a completion port that returns the
// tag.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_latency_tracker
  import kvq_pkg::*;
(
  input  logic           clk,
  input  logic           rst_n,

  input  logic           soft_reset,

  // Tag-issue interface (called when arbiter grants a request)
  input  logic           issue_valid,
  output logic [31:0]    issue_tag,

  // Completion-side: caller provides issued tag, gets latency back
  input  logic [31:0]    complete_tag,
  input  logic [31:0]    complete_deadline,
  output logic [31:0]    complete_latency,
  output logic           complete_deadline_miss,

  // Free-running counter visible to other modules
  output logic [31:0]    cycle_counter
);

  logic [31:0] cycle_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)            cycle_r <= '0;
    else if (soft_reset)   cycle_r <= '0;
    else                    cycle_r <= cycle_r + 32'd1;
  end

  assign cycle_counter = cycle_r;
  assign issue_tag     = cycle_r;

  // Combinational latency math
  always_comb begin
    complete_latency       = cycle_r - complete_tag;
    complete_deadline_miss = (complete_deadline != 32'd0) &&
                             (complete_latency > complete_deadline);
  end

  // issue_valid is observable but not used internally beyond docs/wave aid.
  // Leave it in the port list for clarity and assertion targeting.
  wire _unused_issue_valid = issue_valid;

endmodule : kvq_latency_tracker
