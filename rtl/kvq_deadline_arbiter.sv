// -----------------------------------------------------------------------------
// kvq_deadline_arbiter.sv
//
// Phase 2: pipelined tournament-tree arbiter.
//
// Replaces the Phase 1 single-cycle 8-way priority+slack compare cone (which
// retiming could only shrink from 42 -> 36 logic levels and capped Fmax at
// ~86 MHz) with a 3-level pairwise reduction:
//
//   Stage T1 (8 -> 4 winners):  pairwise(c[0],c[1]) | pairwise(c[2],c[3])
//                               pairwise(c[4],c[5]) | pairwise(c[6],c[7])
//   Stage T2 (4 -> 2 winners):  pairwise(t1[0],t1[1]) | pairwise(t1[2],t1[3])
//   Stage T3 (2 -> 1 winner):   pairwise(t2[0],t2[1])  -> sel_*_q outputs
//
// Each stage has 4-6 logic levels worst case in its pairwise comparator chain,
// so the worst combinational segment between any two registers in the arbiter
// is bounded by a single pairwise_compare.
//
// pairwise_compare semantics (preserving Phase 1 behavior - LOWER priority
// number wins, smaller slack wins, round-robin tiebreak last):
//   - if !a.valid  -> b
//   - if !b.valid  -> a
//   - prio:        smaller wins
//   - slack:       smaller wins on prio tie
//   - rr distance: smaller wins on prio+slack tie (round-robin)
//
// rr_ptr pipelines alongside the candidates so every tournament stage uses
// the same rr_ptr value that was live when this wave's candidates were
// latched at T1. rr_ptr advances when the final stage (T3) emits a grant.
//
// Module port list is unchanged from Phase 1 - kvq_top.sv needs no edits.
// Net latency vs the Phase 1 stage-3 build: +2 cycles (T1, T2 are new;
// the Phase 1 stage-3 register collapses into T3's output register).
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

  // Selected request output to mem_engine
  output logic                            sel_valid,
  input  logic                            sel_ready,
  output kvq_req_t                        sel_req,
  output logic [TENANT_IDX_WIDTH-1:0]     sel_tenant_idx
);

  // ---------------------------------------------------------------------------
  // Tournament-tree carrier type. One per contestant at every tree level.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic                       valid;
    logic [3:0]                 prio;
    logic [31:0]                slack;
    logic [TENANT_IDX_WIDTH-1:0] tid;
    kvq_req_t                   req;
  } cand_t;

  // pairwise comparator. 4-6 logic levels worst case.
  function automatic cand_t pairwise(
    input cand_t                       a,
    input cand_t                       b,
    input logic [TENANT_IDX_WIDTH-1:0] rr
  );
    cand_t                       w;
    logic [TENANT_IDX_WIDTH-1:0] dist_a;
    logic [TENANT_IDX_WIDTH-1:0] dist_b;

    dist_a = a.tid - rr;
    dist_b = b.tid - rr;

    if (!a.valid)               w = b;
    else if (!b.valid)          w = a;
    else if (a.prio  < b.prio)  w = a;
    else if (b.prio  < a.prio)  w = b;
    else if (a.slack < b.slack) w = a;
    else if (b.slack < a.slack) w = b;
    else if (dist_a  < dist_b)  w = a;
    else                        w = b;

    return w;
  endfunction

  // ---------------------------------------------------------------------------
  // Build 8 leaf candidates combinationally from the qmgr inputs.
  // ---------------------------------------------------------------------------
  cand_t                       leaf [0:MAX_TENANTS-1];
  always_comb begin
    for (int t = 0; t < MAX_TENANTS; t++) begin
      leaf[t].valid = deq_valid[t];
      leaf[t].prio  = deq_req[t].prio;
      leaf[t].slack = deq_req[t].deadline_cycles;
      leaf[t].tid   = t[TENANT_IDX_WIDTH-1:0];
      leaf[t].req   = deq_req[t];
    end
  end

  // ---------------------------------------------------------------------------
  // Round-robin pointer (advances when T3 emits a grant). The same rr_ptr
  // value is propagated through the pipeline alongside the candidates so
  // every stage's pairwise uses a consistent tiebreak.
  // ---------------------------------------------------------------------------
  logic [TENANT_IDX_WIDTH-1:0] rr_ptr;

  // ---------------------------------------------------------------------------
  // Pipeline storage
  //   T1 wave: 4 winners + pipelined rr_ptr
  //   T2 wave: 2 winners + pipelined rr_ptr
  //   T3 wave: final winner -> external sel_*_q ports
  // ---------------------------------------------------------------------------
  cand_t                       t1_w   [0:3];
  logic                        t1_valid_q;
  logic [TENANT_IDX_WIDTH-1:0] t1_rr_q;

  cand_t                       t2_w   [0:1];
  logic                        t2_valid_q;
  logic [TENANT_IDX_WIDTH-1:0] t2_rr_q;

  cand_t                       t3_w;
  logic                        sel_valid_q;
  kvq_req_t                    sel_req_q;
  logic [TENANT_IDX_WIDTH-1:0] sel_tid_q;
  logic [MAX_TENANTS-1:0]      deq_grant_q;

  // ---------------------------------------------------------------------------
  // Backpressure: t3 advances when downstream takes the held grant; t2
  // advances when t3 is taking; t1 advances when t2 is taking. When the
  // pipeline stalls (sel_ready = 0 with a held grant), the whole tree
  // freezes.
  // ---------------------------------------------------------------------------
  logic t3_accept;
  logic t2_accept;
  logic t1_accept;
  assign t3_accept = !sel_valid_q || sel_ready;
  assign t2_accept = !t2_valid_q  || t3_accept;
  assign t1_accept = !t1_valid_q  || t2_accept;

  // ---------------------------------------------------------------------------
  // Combinational tournament: produce next-state for each stage from the
  // previous stage's registered output (or the leaf inputs at T1).
  // ---------------------------------------------------------------------------
  cand_t t1_next [0:3];
  cand_t t2_next [0:1];
  cand_t t3_next;
  logic  any_leaf_valid;

  always_comb begin
    t1_next[0]    = pairwise(leaf[0], leaf[1], rr_ptr);
    t1_next[1]    = pairwise(leaf[2], leaf[3], rr_ptr);
    t1_next[2]    = pairwise(leaf[4], leaf[5], rr_ptr);
    t1_next[3]    = pairwise(leaf[6], leaf[7], rr_ptr);
    any_leaf_valid = |deq_valid;

    t2_next[0]   = pairwise(t1_w[0], t1_w[1], t1_rr_q);
    t2_next[1]   = pairwise(t1_w[2], t1_w[3], t1_rr_q);

    t3_next      = pairwise(t2_w[0], t2_w[1], t2_rr_q);
  end

  // ---------------------------------------------------------------------------
  // Pipeline registers
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // T1
      for (int i = 0; i < 4; i++) t1_w[i] <= '0;
      t1_valid_q <= 1'b0;
      t1_rr_q    <= '0;
      // T2
      for (int i = 0; i < 2; i++) t2_w[i] <= '0;
      t2_valid_q <= 1'b0;
      t2_rr_q    <= '0;
      // T3 outputs
      sel_valid_q <= 1'b0;
      sel_req_q   <= '0;
      sel_tid_q   <= '0;
      deq_grant_q <= '0;
      t3_w        <= '0;
    end else begin
      // T1 advance
      if (t1_accept) begin
        for (int i = 0; i < 4; i++) t1_w[i] <= t1_next[i];
        t1_valid_q <= any_leaf_valid;
        t1_rr_q    <= rr_ptr;
      end
      // T2 advance
      if (t2_accept) begin
        for (int i = 0; i < 2; i++) t2_w[i] <= t2_next[i];
        t2_valid_q <= t1_valid_q;
        t2_rr_q    <= t1_rr_q;
      end
      // T3 advance: latch the final winner and pulse deq_grant_q for
      // exactly one cycle when the slice latches a new selection.
      deq_grant_q <= '0;
      if (t3_accept) begin
        t3_w <= t3_next;
        sel_valid_q <= t2_valid_q && t3_next.valid;
        if (t2_valid_q && t3_next.valid) begin
          sel_req_q             <= t3_next.req;
          sel_tid_q             <= t3_next.tid;
          deq_grant_q[t3_next.tid] <= 1'b1;
        end
      end
    end
  end

  assign sel_valid      = sel_valid_q;
  assign sel_req        = sel_req_q;
  assign sel_tenant_idx = sel_tid_q;
  assign deq_grant      = deq_grant_q;

  // ---------------------------------------------------------------------------
  // rr_ptr: advance when T3 emits a fresh grant.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rr_ptr <= '0;
    end else if (t3_accept && t2_valid_q && t3_next.valid) begin
      rr_ptr <= (t3_next.tid == MAX_TENANTS-1) ? '0 : t3_next.tid + 1'b1;
    end
  end

endmodule : kvq_deadline_arbiter
