// -----------------------------------------------------------------------------
// kvq_token_bucket.sv
// Single-tenant token-bucket primitive. Used by kvq_credit_engine which
// instantiates MAX_TENANTS copies. Saturating refill, saturating consume,
// no underflow, deterministic reset.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_token_bucket
  import kvq_pkg::*;
#(
  parameter int CREDIT_W = CREDIT_WIDTH
) (
  input  logic                  clk,
  input  logic                  rst_n,

  // Configuration (live; latched cycle-by-cycle from contract table)
  input  logic [CREDIT_W-1:0]   burst_credit_limit,
  input  logic [15:0]           refill_amount,

  // Refill pulse (driven by credit_engine's refill scheduler)
  input  logic                  refill_enable,

  // Consume request: deduct consume_amount on the same cycle that
  // consume_valid is high. Engine guarantees consume_amount <= credit_value.
  input  logic                  consume_valid,
  input  logic [7:0]            consume_amount,

  // Outputs
  output logic                  credit_available,
  output logic [CREDIT_W-1:0]   credit_value
);

  logic [CREDIT_W-1:0] credit_r;
  logic [CREDIT_W:0]   refilled;
  logic [CREDIT_W:0]   next_credit;

  always_comb begin
    // Refill (saturating to burst_credit_limit)
    refilled = {1'b0, credit_r} + (refill_enable ? {1'b0, {{(CREDIT_W-16){1'b0}}, refill_amount}} : '0);
    if (refilled > {1'b0, burst_credit_limit}) begin
      refilled = {1'b0, burst_credit_limit};
    end

    // Consume (saturating to zero)
    if (consume_valid) begin
      if (refilled >= {1'b0, {{(CREDIT_W-8){1'b0}}, consume_amount}}) begin
        next_credit = refilled - {1'b0, {{(CREDIT_W-8){1'b0}}, consume_amount}};
      end else begin
        next_credit = '0;
      end
    end else begin
      next_credit = refilled;
    end
  end

  // Bucket starts saturated to the burst_credit_limit input so the first
  // request after reset has credit. We track an init pulse off rst_n so that
  // the live burst_credit_limit (which is itself reset to a known value in
  // kvq_credit_engine) is sampled before normal saturating arithmetic begins.
  logic init_done;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      credit_r  <= '1;          // start with maximum credits; refill clamps later
      init_done <= 1'b0;
    end else if (!init_done) begin
      credit_r  <= burst_credit_limit;
      init_done <= 1'b1;
    end else begin
      credit_r <= next_credit[CREDIT_W-1:0];
    end
  end

  assign credit_value     = credit_r;
  assign credit_available = (credit_r != '0);

endmodule : kvq_token_bucket
