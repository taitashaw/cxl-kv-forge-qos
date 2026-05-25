// -----------------------------------------------------------------------------
// kvq_credit_engine.sv
// Per-tenant credit enforcement built on top of MAX_TENANTS instances of
// kvq_token_bucket. Each cycle, an upstream request can either be accepted
// (credits available, deducted in this cycle) or stalled. If accepted, the
// request is forwarded to the per-tenant queue manager.
//
// Refill: simple periodic refill of contract.min_bandwidth credits every
// REFILL_PERIOD_CYCLES cycles, saturated to contract.burst_credit_limit.
//
// Outputs a credit_snapshot for telemetry (selected tenant's current credit).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_credit_engine
  import kvq_pkg::*;
#(
  parameter int REFILL_PERIOD_CYCLES = 64
) (
  input  logic                          clk,
  input  logic                          rst_n,

  // Per-tenant contracts (broadcast snapshot)
  input  logic [TENANT_ID_WIDTH-1:0]    req_tenant_id,
  input  kvq_contract_t                 req_contract,

  // Upstream request handshake (from parser)
  input  logic                          in_valid,
  output logic                          in_ready,
  input  kvq_req_t                      in_req,
  input  logic                          in_bad_opcode,
  input  logic                          in_bad_framing,

  // Downstream to queue manager
  output logic                          out_valid,
  input  logic                          out_ready,
  output kvq_req_t                      out_req,

  // Error side-channel (to error_handler / response_builder)
  output logic                          err_valid,
  input  logic                          err_ready,
  output kvq_req_t                      err_req,
  output logic [7:0]                    err_status,

  // Telemetry
  output logic [31:0]                   credit_snapshot,
  output logic                          credit_starvation_pulse
);

  // Per-tenant buckets
  logic [CREDIT_WIDTH-1:0] bucket_credit  [0:MAX_TENANTS-1];
  logic                    bucket_avail   [0:MAX_TENANTS-1];

  // Refill timer
  logic [$clog2(REFILL_PERIOD_CYCLES+1)-1:0] refill_cnt;
  logic                                       refill_pulse;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      refill_cnt   <= '0;
      refill_pulse <= 1'b0;
    end else begin
      if (refill_cnt == (REFILL_PERIOD_CYCLES-1)) begin
        refill_cnt   <= '0;
        refill_pulse <= 1'b1;
      end else begin
        refill_cnt   <= refill_cnt + 1'b1;
        refill_pulse <= 1'b0;
      end
    end
  end

  // Instantiate MAX_TENANTS token buckets. Each bucket sees the contract for
  // tenant i = its index. Because contracts are fetched combinationally via
  // tenant_id, the refill amount per cycle is the per-tenant contract's
  // min_bandwidth (which we sample by hooking each bucket up to a tenant-
  // -indexed contract latch). For Phase 1 we accept a simplification: the
  // refill amount is the same across buckets (req_contract.min_bandwidth)
  // when the engine is observing that tenant; otherwise the bucket holds
  // its current level.
  //
  // Better behavior in a future revision: snapshot all 8 contracts into a
  // local array and refill them in parallel.

  logic [15:0]               bucket_refill_amt [0:MAX_TENANTS-1];
  logic [CREDIT_WIDTH-1:0]   bucket_burst_lim  [0:MAX_TENANTS-1];

  // Latched per-tenant contract snapshot
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int t = 0; t < MAX_TENANTS; t++) begin
        bucket_refill_amt[t] <= 16'd1;
        bucket_burst_lim[t]  <= 32'd16;
      end
    end else if (req_tenant_id[TENANT_IDX_WIDTH-1:0] < MAX_TENANTS) begin
      bucket_refill_amt[req_tenant_id[TENANT_IDX_WIDTH-1:0]] <= req_contract.min_bandwidth;
      bucket_burst_lim[req_tenant_id[TENANT_IDX_WIDTH-1:0]]  <= req_contract.burst_credit_limit;
    end
  end

  // Determine consume signal for this cycle
  logic                       want_consume;
  logic [7:0]                 want_amount;
  logic [TENANT_IDX_WIDTH-1:0] tenant_idx;
  logic                       credit_ok;

  assign tenant_idx   = in_req.tenant_id[TENANT_IDX_WIDTH-1:0];
  assign want_amount  = kvq_service_units(in_req.opcode);
  assign credit_ok    = (bucket_credit[tenant_idx] >= {{(CREDIT_WIDTH-8){1'b0}}, want_amount});
  assign want_consume = in_valid && !in_bad_opcode && !in_bad_framing && credit_ok && out_ready;

  // Instantiate buckets
  genvar gi;
  generate
    for (gi = 0; gi < MAX_TENANTS; gi++) begin : g_buckets
      logic consume_this;
      assign consume_this = want_consume && (tenant_idx == gi[TENANT_IDX_WIDTH-1:0]);

      kvq_token_bucket #(
        .CREDIT_W(CREDIT_WIDTH)
      ) u_bucket (
        .clk               (clk),
        .rst_n             (rst_n),
        .burst_credit_limit(bucket_burst_lim[gi]),
        .refill_amount     (bucket_refill_amt[gi]),
        .refill_enable     (refill_pulse),
        .consume_valid     (consume_this),
        .consume_amount    (want_amount),
        .credit_available  (bucket_avail[gi]),
        .credit_value      (bucket_credit[gi])
      );
    end
  endgenerate

  // Handshakes
  // Three downstream paths from a request:
  //  - bad opcode/framing -> err path with bad-opcode status
  //  - no credit          -> err path with no-credit status
  //  - good               -> queue path
  logic forward_good;
  logic forward_err;

  assign forward_good = in_valid && !in_bad_opcode && !in_bad_framing && credit_ok;
  assign forward_err  = in_valid &&  (in_bad_opcode || in_bad_framing || !credit_ok);

  assign in_ready = (forward_good ? out_ready : (forward_err ? err_ready : 1'b1));

  assign out_valid = forward_good;
  assign out_req   = in_req;

  assign err_valid = forward_err;
  assign err_req   = in_req;
  assign err_status = in_bad_opcode  ? KVQ_STATUS_ERR_BAD_OPCODE :
                      in_bad_framing ? KVQ_STATUS_ERR_INTERNAL   :
                                       KVQ_STATUS_ERR_NO_CREDIT;

  // Telemetry
  assign credit_snapshot         = bucket_credit[tenant_idx];
  assign credit_starvation_pulse = in_valid && !in_bad_opcode && !in_bad_framing && !credit_ok;

endmodule : kvq_credit_engine
