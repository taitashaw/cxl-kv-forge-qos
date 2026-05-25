// -----------------------------------------------------------------------------
// kvq_perf_counters.sv
// Thin readback wrapper around kvq_sla_monitor counters. Splits the counter
// fan-out away from the AXI4-Lite shim so that future extensions (per-tenant
// counter banks, histograms, etc.) can attach here without touching axil_regs.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_perf_counters
  import kvq_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // SLA-monitor inputs (already 32-bit registered upstream)
  input  logic [31:0] cnt_total_requests,
  input  logic [31:0] cnt_read_requests,
  input  logic [31:0] cnt_write_requests,
  input  logic [31:0] cnt_prefetch_requests,
  input  logic [31:0] cnt_deadline_miss,
  input  logic [31:0] cnt_credit_starvation,
  input  logic [31:0] cnt_malformed_request,
  input  logic [31:0] cnt_input_backpressure,
  input  logic [31:0] cnt_output_backpressure,
  input  logic [31:0] cnt_max_latency,
  input  logic [31:0] cnt_cumulative_latency,
  input  logic [15:0] cnt_max_queue_occupancy,

  // Readback bus used by axil_regs (addr-indexed mux)
  input  logic [3:0]  rb_sel,
  output logic [31:0] rb_data
);

  always_comb begin
    unique case (rb_sel)
      4'd0:  rb_data = cnt_total_requests;
      4'd1:  rb_data = cnt_read_requests;
      4'd2:  rb_data = cnt_write_requests;
      4'd3:  rb_data = cnt_prefetch_requests;
      4'd4:  rb_data = cnt_deadline_miss;
      4'd5:  rb_data = cnt_credit_starvation;
      4'd6:  rb_data = cnt_malformed_request;
      4'd7:  rb_data = cnt_input_backpressure;
      4'd8:  rb_data = cnt_output_backpressure;
      4'd9:  rb_data = cnt_max_latency;
      4'd10: rb_data = cnt_cumulative_latency;
      4'd11: rb_data = {16'd0, cnt_max_queue_occupancy};
      default: rb_data = 32'h0;
    endcase
  end

endmodule : kvq_perf_counters
