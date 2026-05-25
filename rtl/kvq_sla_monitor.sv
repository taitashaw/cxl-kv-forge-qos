// -----------------------------------------------------------------------------
// kvq_sla_monitor.sv
// Aggregates Phase 1 global counters. Percentile histograms remain Python-side
// for now. Counters are exposed to kvq_axil_regs through a flat output bundle.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_sla_monitor
  import kvq_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        counter_reset,

  // Event hooks
  input  logic        ev_req_accepted,        // a request was admitted to the queue
  input  logic [7:0]  ev_req_opcode,
  input  logic        ev_response_emitted,
  input  logic        ev_deadline_miss,
  input  logic        ev_credit_starvation,
  input  logic        ev_malformed_request,
  input  logic        ev_in_backpressure,     // sampled per cycle
  input  logic        ev_out_backpressure,    // sampled per cycle
  input  logic [31:0] ev_latency_cycles,
  input  logic [15:0] ev_queue_occupancy,

  // Counter outputs
  output logic [31:0] cnt_total_requests,
  output logic [31:0] cnt_read_requests,
  output logic [31:0] cnt_write_requests,
  output logic [31:0] cnt_prefetch_requests,
  output logic [31:0] cnt_deadline_miss,
  output logic [31:0] cnt_credit_starvation,
  output logic [31:0] cnt_malformed_request,
  output logic [31:0] cnt_input_backpressure,
  output logic [31:0] cnt_output_backpressure,
  output logic [31:0] cnt_max_latency,
  output logic [31:0] cnt_cumulative_latency,
  output logic [15:0] cnt_max_queue_occupancy
);

  logic [31:0] r_total;
  logic [31:0] r_read;
  logic [31:0] r_write;
  logic [31:0] r_prefetch;
  logic [31:0] r_dmiss;
  logic [31:0] r_starv;
  logic [31:0] r_malformed;
  logic [31:0] r_ibp;
  logic [31:0] r_obp;
  logic [31:0] r_maxlat;
  logic [31:0] r_cumlat;
  logic [15:0] r_maxocc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || counter_reset) begin
      r_total     <= '0;
      r_read      <= '0;
      r_write     <= '0;
      r_prefetch  <= '0;
      r_dmiss     <= '0;
      r_starv     <= '0;
      r_malformed <= '0;
      r_ibp       <= '0;
      r_obp       <= '0;
      r_maxlat    <= '0;
      r_cumlat    <= '0;
      r_maxocc    <= '0;
    end else begin
      if (ev_req_accepted) begin
        r_total <= r_total + 32'd1;
        unique case (ev_req_opcode)
          KVQ_OP_READ:     r_read     <= r_read     + 32'd1;
          KVQ_OP_WRITE:    r_write    <= r_write    + 32'd1;
          KVQ_OP_PREFETCH: r_prefetch <= r_prefetch + 32'd1;
          default: ;
        endcase
      end

      if (ev_deadline_miss)      r_dmiss     <= r_dmiss     + 32'd1;
      if (ev_credit_starvation)  r_starv     <= r_starv     + 32'd1;
      if (ev_malformed_request)  r_malformed <= r_malformed + 32'd1;
      if (ev_in_backpressure)    r_ibp       <= r_ibp       + 32'd1;
      if (ev_out_backpressure)   r_obp       <= r_obp       + 32'd1;

      if (ev_response_emitted) begin
        r_cumlat <= r_cumlat + ev_latency_cycles;
        if (ev_latency_cycles > r_maxlat) r_maxlat <= ev_latency_cycles;
      end

      if (ev_queue_occupancy > r_maxocc) r_maxocc <= ev_queue_occupancy;
    end
  end

  assign cnt_total_requests       = r_total;
  assign cnt_read_requests        = r_read;
  assign cnt_write_requests       = r_write;
  assign cnt_prefetch_requests    = r_prefetch;
  assign cnt_deadline_miss        = r_dmiss;
  assign cnt_credit_starvation    = r_starv;
  assign cnt_malformed_request    = r_malformed;
  assign cnt_input_backpressure   = r_ibp;
  assign cnt_output_backpressure  = r_obp;
  assign cnt_max_latency          = r_maxlat;
  assign cnt_cumulative_latency   = r_cumlat;
  assign cnt_max_queue_occupancy  = r_maxocc;

endmodule : kvq_sla_monitor
