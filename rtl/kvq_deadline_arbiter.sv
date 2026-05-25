// -----------------------------------------------------------------------------
// kvq_deadline_arbiter.sv
// Picks one non-empty tenant queue per cycle subject to:
//   1) lowest priority_class wins
//   2) smallest deadline slack wins
//   3) round-robin tie-break
//
// For Phase 1, deadline slack is computed as (req.deadline_cycles) relative to
// a free-running cycle counter snapshot of when the head-of-queue request was
// enqueued. Because the queue manager does not retain enqueue timestamps in
// MVP, we use the head request's raw deadline_cycles field as the slack
// surrogate. This is correct enough for ordering during Phase 1; refined slack
// tracking is a Phase 2 task.
//
// Single-stage combinational arbitration. One-hot deq_grant pulses when
// downstream (latency_tracker / memory_engine) is ready.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_deadline_arbiter
  import kvq_pkg::*;
(
  input  logic                            clk,
  input  logic                            rst_n,

  // Per-tenant inputs from queue manager
  input  logic [MAX_TENANTS-1:0]          deq_valid,
  input  kvq_req_t                        deq_req      [0:MAX_TENANTS-1],
  output logic [MAX_TENANTS-1:0]          deq_grant,

  // Per-tenant priority_class snapshot (driven by top from contract table
  // for the *head* request's tenant); MVP uses the head request's own
  // .priority field.
  // (No external priority input - we use req.priority bits 3:0.)

  // Selected request output to latency_tracker
  output logic                            sel_valid,
  input  logic                            sel_ready,
  output kvq_req_t                        sel_req,
  output logic [TENANT_IDX_WIDTH-1:0]     sel_tenant_idx
);

  logic [TENANT_IDX_WIDTH-1:0] rr_ptr;

  logic [TENANT_IDX_WIDTH-1:0] best_idx;
  logic                        best_found;
  logic [3:0]                  best_prio;
  logic [31:0]                 best_slack;
  logic [TENANT_IDX_WIDTH-1:0] cand;
  integer                      i;
  integer                      offset;

  always_comb begin
    best_found = 1'b0;
    best_idx   = '0;
    best_prio  = 4'hF;
    best_slack = 32'hFFFFFFFF;

    for (offset = 0; offset < MAX_TENANTS; offset = offset + 1) begin
      // Walk tenants starting from rr_ptr to enforce round-robin tie-break.
      cand = (rr_ptr + offset[TENANT_IDX_WIDTH-1:0]) % MAX_TENANTS;
      if (deq_valid[cand]) begin
        logic [3:0]  c_prio;
        logic [31:0] c_slack;
        c_prio  = deq_req[cand].prio;
        c_slack = deq_req[cand].deadline_cycles;

        if (!best_found ||
            (c_prio < best_prio) ||
            ((c_prio == best_prio) && (c_slack < best_slack))) begin
          best_found = 1'b1;
          best_idx   = cand;
          best_prio  = c_prio;
          best_slack = c_slack;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Stage-3 output register (the 3rd arbitration pipeline stage).
  //
  // The first two stages live inside the queue manager (deq_req_r and
  // deq_grant_r). This stage caps the path: the combinational winner-mux
  // output is latched here instead of flowing directly into u_mem. With
  // retiming_backward = 1 Vivado synth is permitted to pull the inserted
  // register back through the 42-level mux cone in u_arb, splitting it into
  // shorter sub-paths.
  //
  // Handshake: behaves as a single-stage register slice. The slice accepts
  // a new selection when its output is empty (sel_valid_q = 0) or when the
  // consumer is taking the held value this cycle (sel_ready = 1). deq_grant
  // pulses for exactly one cycle when the slice latches a new selection,
  // so the qmgr's q_head only advances once per accepted request even if
  // the slice subsequently stalls.
  // ---------------------------------------------------------------------------

  (* retiming_backward = 1, retiming_forward = 0 *) logic                       sel_valid_q;
  (* retiming_backward = 1, retiming_forward = 0 *) kvq_req_t                   sel_req_q;
  (* retiming_backward = 1, retiming_forward = 0 *) logic [TENANT_IDX_WIDTH-1:0] sel_tid_q;
  (* retiming_backward = 1, retiming_forward = 0 *) logic [MAX_TENANTS-1:0]     deq_grant_q;
  (* retiming_backward = 1, retiming_forward = 0 *) logic [3:0]                 best_prio_q;
  (* retiming_backward = 1, retiming_forward = 0 *) logic [31:0]                best_slack_q;

  logic accept_new;
  assign accept_new = !sel_valid_q || sel_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sel_valid_q  <= 1'b0;
      sel_req_q    <= '0;
      sel_tid_q    <= '0;
      deq_grant_q  <= '0;
      best_prio_q  <= '0;
      best_slack_q <= '0;
    end else begin
      // Always pulse deq_grant_q for exactly one cycle on the accept edge.
      deq_grant_q <= '0;
      if (accept_new) begin
        sel_valid_q <= best_found;
        if (best_found) begin
          sel_req_q             <= deq_req[best_idx];
          sel_tid_q             <= best_idx;
          deq_grant_q[best_idx] <= 1'b1;
          best_prio_q           <= best_prio;
          best_slack_q          <= best_slack;
        end
      end
    end
  end

  assign sel_valid      = sel_valid_q;
  assign sel_req        = sel_req_q;
  assign sel_tenant_idx = sel_tid_q;
  assign deq_grant      = deq_grant_q;

  // Round-robin pointer advances on the same condition the slice accepts
  // a new winner.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rr_ptr <= '0;
    end else if (accept_new && best_found) begin
      rr_ptr <= (best_idx == MAX_TENANTS-1) ? '0 : best_idx + 1'b1;
    end
  end

endmodule : kvq_deadline_arbiter
