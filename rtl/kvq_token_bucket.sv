// -----------------------------------------------------------------------------
// kvq_token_bucket.sv
//
// Phase 2.1: pipelined saturating-arithmetic.
//
// The Phase 2 closure exposed this module's combinational refill+clamp+consume
// chain as the next bottleneck (12 logic levels through a 32-bit CARRY8
// adder + compare + subtract on the same register's next-state cone).
//
// One bucket-add split, as authorized by the Phase 2.1 spec, broken at the
// refill-to-consume boundary rather than at bit 16 of the adder: a single
// pipeline register sits between the refill saturation and the consume
// saturation. Each half is now ~6-7 logic levels deep.
//
//   Stage 1 (refill):   credit_r + refill_amount  ->  clamp to burst_limit
//                       result registered into refilled_q
//   Stage 2 (consume):  refilled_q - consume_amount -> saturate to zero
//                       result registered into credit_r
//
// Net latency: 2 cycles from a refill_enable pulse (or a consume_valid
// pulse) to its effect appearing on credit_r / credit_available. The
// Phase 2.1 spec explicitly authorizes a +1 cycle latency hit.
//
// credit_available is unchanged - still a single-bit derivative of the
// registered credit_r, as required by the Phase 2.1 spec ("credit_avail
// must use the registered post-saturation credit_r value, not any
// combinational midpoint").
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

  input  logic [CREDIT_W-1:0]   burst_credit_limit,
  input  logic [15:0]           refill_amount,

  input  logic                  refill_enable,

  input  logic                  consume_valid,
  input  logic [7:0]            consume_amount,

  output logic                  credit_available,
  output logic [CREDIT_W-1:0]   credit_value
);

  // ---------------------------------------------------------------------------
  // Stage-1 combinational: refill add + clamp to burst_credit_limit
  // ---------------------------------------------------------------------------
  logic [CREDIT_W:0]   refill_sum;
  logic [CREDIT_W-1:0] refilled_d;

  logic [CREDIT_W-1:0] credit_r;

  always_comb begin
    refill_sum = {1'b0, credit_r} +
                 (refill_enable
                    ? {1'b0, {{(CREDIT_W-16){1'b0}}, refill_amount}}
                    : {(CREDIT_W+1){1'b0}});
    if (refill_sum > {1'b0, burst_credit_limit}) begin
      refilled_d = burst_credit_limit;
    end else begin
      refilled_d = refill_sum[CREDIT_W-1:0];
    end
  end

  // ---------------------------------------------------------------------------
  // Pipeline registers between stage 1 and stage 2.
  // refilled_q holds the post-clamp refill result; consume_valid and
  // consume_amount also pipeline so stage 2 applies the consume to the
  // same wave's refilled value.
  // ---------------------------------------------------------------------------
  logic [CREDIT_W-1:0] refilled_q;
  logic                consume_valid_q;
  logic [7:0]          consume_amount_q;

  // Init-pulse keeps the Phase 1 semantic of "start full" - on the first
  // post-reset cycle credit_r gets burst_credit_limit, and refilled_q
  // tracks it so stage 2 has a sane starting point.
  logic init_done;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      refilled_q       <= '1;
      consume_valid_q  <= 1'b0;
      consume_amount_q <= '0;
      init_done        <= 1'b0;
    end else if (!init_done) begin
      refilled_q       <= burst_credit_limit;
      consume_valid_q  <= 1'b0;
      consume_amount_q <= '0;
      init_done        <= 1'b1;
    end else begin
      refilled_q       <= refilled_d;
      consume_valid_q  <= consume_valid;
      consume_amount_q <= consume_amount;
    end
  end

  // ---------------------------------------------------------------------------
  // Stage-2 combinational: consume + saturate-to-zero
  // ---------------------------------------------------------------------------
  logic [CREDIT_W-1:0] next_credit;
  logic [CREDIT_W-1:0] consume_zext;
  assign consume_zext = {{(CREDIT_W-8){1'b0}}, consume_amount_q};

  always_comb begin
    if (consume_valid_q) begin
      if (refilled_q >= consume_zext) begin
        next_credit = refilled_q - consume_zext;
      end else begin
        next_credit = '0;
      end
    end else begin
      next_credit = refilled_q;
    end
  end

  // ---------------------------------------------------------------------------
  // Final register: credit_r (the value credit_engine reads via credit_value
  // / credit_available).
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      credit_r <= '1;
    end else if (!init_done) begin
      credit_r <= burst_credit_limit;
    end else begin
      credit_r <= next_credit;
    end
  end

  assign credit_value     = credit_r;
  assign credit_available = (credit_r != '0);

endmodule : kvq_token_bucket
