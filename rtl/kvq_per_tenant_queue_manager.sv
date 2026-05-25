// -----------------------------------------------------------------------------
// kvq_per_tenant_queue_manager.sv
// One logical FIFO per tenant, depth TENANT_QUEUE_DEPTH. Implemented as a
// flat register file with per-tenant head/tail/count pointers. Enforces
// per-tenant max_queue_depth from the contract table; over-cap enqueues are
// dropped to the error side-channel as KVQ_STATUS_ERR_QUEUE_FULL.
//
// Phase 1 sizing: MAX_TENANTS x TENANT_QUEUE_DEPTH = 8 x 16 = 128 entries of
// kvq_req_t each. Acceptable on ZCU102 in distributed RAM. Future revisions
// can pack into per-tenant BRAMs.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_per_tenant_queue_manager
  import kvq_pkg::*;
(
  input  logic                              clk,
  input  logic                              rst_n,

  input  logic                              soft_reset,

  // Enqueue port (from credit_engine)
  input  logic                              enq_valid,
  output logic                              enq_ready,
  input  kvq_req_t                          enq_req,
  input  logic [15:0]                       enq_max_depth, // from contract

  // Queue-full error side-channel
  output logic                              full_err_valid,
  output kvq_req_t                          full_err_req,

  // Dequeue port (to arbiter): MAX_TENANTS independent ports
  output logic [MAX_TENANTS-1:0]            deq_valid,
  output kvq_req_t                          deq_req      [0:MAX_TENANTS-1],
  input  logic [MAX_TENANTS-1:0]            deq_grant,   // arbiter pulses one bit when it takes

  // Observability
  output logic [15:0]                       global_queue_occupancy,
  output logic [QUEUE_OCC_WIDTH-1:0]        per_tenant_occupancy [0:MAX_TENANTS-1],
  output logic                              queue_full
);

  localparam int Q_PTR_W = $clog2(TENANT_QUEUE_DEPTH);

  kvq_req_t                  q_mem  [0:MAX_TENANTS-1][0:TENANT_QUEUE_DEPTH-1];
  logic [Q_PTR_W-1:0]        q_head [0:MAX_TENANTS-1];
  logic [Q_PTR_W-1:0]        q_tail [0:MAX_TENANTS-1];
  logic [QUEUE_OCC_WIDTH-1:0] q_count[0:MAX_TENANTS-1];

  logic [TENANT_IDX_WIDTH-1:0] enq_idx;
  logic                        enq_accept;
  logic                        enq_reject_full;

  assign enq_idx = enq_req.tenant_id[TENANT_IDX_WIDTH-1:0];

  // Per-tenant cap: min(global queue depth, contract.max_queue_depth)
  logic [QUEUE_OCC_WIDTH-1:0] effective_cap;
  always_comb begin
    if (enq_max_depth >= TENANT_QUEUE_DEPTH) begin
      effective_cap = QUEUE_OCC_WIDTH'(TENANT_QUEUE_DEPTH);
    end else begin
      effective_cap = enq_max_depth[QUEUE_OCC_WIDTH-1:0];
    end
  end

  assign enq_accept      = enq_valid && (q_count[enq_idx] < effective_cap);
  assign enq_reject_full = enq_valid && (q_count[enq_idx] >= effective_cap);
  assign enq_ready       = !enq_valid || enq_accept || enq_reject_full;

  // Full-error side-channel (1 cycle pulse)
  logic full_err_valid_r;
  kvq_req_t full_err_req_r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      full_err_valid_r <= 1'b0;
      full_err_req_r   <= '0;
    end else begin
      full_err_valid_r <= enq_reject_full;
      if (enq_reject_full) full_err_req_r <= enq_req;
    end
  end
  assign full_err_valid = full_err_valid_r;
  assign full_err_req   = full_err_req_r;

  // ---------------------------------------------------------------------------
  // Pipeline for 400 MHz closure
  //
  // The previous design had a single combinational loop from q_head[t] through
  // q_mem readout, through the arbiter's comparison tree, and back to
  // q_head[t'].CE. At 400 MHz (2.5 ns period) that path could not close on
  // xczu3eg (the post-route critical path was 4.21 ns logic + 10.1 ns route).
  //
  // We register the loop at two points, both inside this module so the
  // arbiter remains combinational and its protocol is unchanged:
  //   stage A: deq_req / deq_valid output  - registered q_mem readout
  //   stage B: deq_grant input from arb    - registered before q_head update
  //
  // Net latency cost: +2 cycles for a request to traverse the arbitration
  // path. Throughput is unchanged because the memory engine pipeline already
  // takes >=4 cycles per request.
  // ---------------------------------------------------------------------------

  // Stage A registers
  kvq_req_t                deq_req_r   [0:MAX_TENANTS-1];
  logic [MAX_TENANTS-1:0]  deq_valid_r;

  // Stage B register (the qmgr-internal view of the arbiter's deq_grant)
  logic [MAX_TENANTS-1:0]  deq_grant_r;

  // Pointer / memory update - q_head and q_count now consume deq_grant_r.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int t = 0; t < MAX_TENANTS; t = t + 1) begin
        q_head[t]  <= '0;
        q_tail[t]  <= '0;
        q_count[t] <= '0;
      end
      deq_grant_r <= '0;
    end else if (soft_reset) begin
      for (int t = 0; t < MAX_TENANTS; t = t + 1) begin
        q_head[t]  <= '0;
        q_tail[t]  <= '0;
        q_count[t] <= '0;
      end
      deq_grant_r <= '0;
    end else begin
      // Stage B: latch arbiter grant for use next cycle
      deq_grant_r <= deq_grant;

      // Enqueue
      if (enq_accept) begin
        q_mem[enq_idx][q_tail[enq_idx]] <= enq_req;
        q_tail[enq_idx]                  <= (q_tail[enq_idx] == TENANT_QUEUE_DEPTH-1) ?
                                            '0 : q_tail[enq_idx] + 1'b1;
      end

      // Dequeue using the registered grant - the q_head update is now
      // timed against deq_grant_r instead of the combinational arbiter output.
      for (int t = 0; t < MAX_TENANTS; t = t + 1) begin
        if (deq_grant_r[t] && (q_count[t] != 0)) begin
          q_head[t] <= (q_head[t] == TENANT_QUEUE_DEPTH-1) ? '0 : q_head[t] + 1'b1;
        end
      end

      // Count update (handle simultaneous enq+deq on same tenant)
      for (int t = 0; t < MAX_TENANTS; t = t + 1) begin
        logic enq_here;
        logic deq_here;
        enq_here = enq_accept && (enq_idx == t[TENANT_IDX_WIDTH-1:0]);
        deq_here = deq_grant_r[t] && (q_count[t] != 0);
        unique case ({enq_here, deq_here})
          2'b10: q_count[t] <= q_count[t] + 1'b1;
          2'b01: q_count[t] <= q_count[t] - 1'b1;
          2'b11: q_count[t] <= q_count[t];
          default: ;
        endcase
      end
    end
  end

  // Stage A: register the head readout. deq_req_r / deq_valid_r drive the
  // arbiter; the arbiter sees the q_head-indexed q_mem entry one cycle late.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int j = 0; j < MAX_TENANTS; j = j + 1) deq_req_r[j] <= '0;
      deq_valid_r <= '0;
    end else if (soft_reset) begin
      for (int j = 0; j < MAX_TENANTS; j = j + 1) deq_req_r[j] <= '0;
      deq_valid_r <= '0;
    end else begin
      for (int j = 0; j < MAX_TENANTS; j = j + 1) begin
        deq_valid_r[j] <= (q_count[j] != 0);
        deq_req_r[j]   <= q_mem[j][q_head[j]];
      end
    end
  end

  // Head readout port - drives the arbiter, registered (stage A)
  always_comb begin
    for (int j = 0; j < MAX_TENANTS; j++) begin
      deq_valid[j] = deq_valid_r[j];
      deq_req[j]   = deq_req_r[j];
    end
  end

  // Observability
  always_comb begin
    global_queue_occupancy = '0;
    for (int k = 0; k < MAX_TENANTS; k++) begin
      per_tenant_occupancy[k] = q_count[k];
      global_queue_occupancy  = global_queue_occupancy + {{16-QUEUE_OCC_WIDTH{1'b0}}, q_count[k]};
    end
  end

  // Aggregate full flag
  logic any_full;
  always_comb begin
    any_full = 1'b0;
    for (int m = 0; m < MAX_TENANTS; m++) begin
      if (q_count[m] >= TENANT_QUEUE_DEPTH) any_full = 1'b1;
    end
  end
  assign queue_full = any_full;

endmodule : kvq_per_tenant_queue_manager
