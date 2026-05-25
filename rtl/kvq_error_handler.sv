// -----------------------------------------------------------------------------
// kvq_error_handler.sv
// Funnels error events from multiple sources into a single error stream that
// feeds the response builder. Sources:
//   - bad opcode / framing from kvq_request_parser (via credit_engine.err_*)
//   - no-credit from kvq_credit_engine
//   - queue-full from kvq_per_tenant_queue_manager
//   - bad tenant (reserved for future use)
// Request_id and tenant_id are preserved end-to-end.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_error_handler
  import kvq_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // From credit engine (bad opcode, no credit)
  input  logic        ce_err_valid,
  output logic        ce_err_ready,
  input  kvq_req_t    ce_err_req,
  input  logic [7:0]  ce_err_status,

  // From queue manager (queue full)
  input  logic        qm_full_valid,
  input  kvq_req_t    qm_full_req,

  // To response builder
  output logic        err_valid,
  input  logic        err_ready,
  output kvq_req_t    err_req,
  output logic [7:0]  err_status
);

  // Single-entry holding register (Phase 1 MVP: drop any second concurrent
  // error and bump malformed_request_count via SLA monitor)
  kvq_req_t   hold_req;
  logic [7:0] hold_status;
  logic       hold_valid;

  assign ce_err_ready = !hold_valid || err_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      hold_valid  <= 1'b0;
      hold_req    <= '0;
      hold_status <= '0;
    end else begin
      if (err_valid && err_ready) begin
        hold_valid <= 1'b0;
      end
      // Priority: credit-engine path then queue-manager path
      if (!hold_valid || (err_valid && err_ready)) begin
        if (ce_err_valid) begin
          hold_req    <= ce_err_req;
          hold_status <= ce_err_status;
          hold_valid  <= 1'b1;
        end else if (qm_full_valid) begin
          hold_req    <= qm_full_req;
          hold_status <= KVQ_STATUS_ERR_QUEUE_FULL;
          hold_valid  <= 1'b1;
        end
      end
    end
  end

  assign err_valid  = hold_valid;
  assign err_req    = hold_req;
  assign err_status = hold_status;

endmodule : kvq_error_handler
