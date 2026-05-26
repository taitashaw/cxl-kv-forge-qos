// -----------------------------------------------------------------------------
// kvq_memory_engine.sv
// Single-issue Phase 1 memory engine. Accepts one request at a time from the
// arbiter, optionally inserts MEM_LATENCY_CYCLES of synthetic delay, then
// performs a BRAM read or write and produces a memory-response that the
// response_builder converts into an AXIS response.
//
// Opcode handling:
//   READ        - BRAM read; status OK on hit, MISS on cold address
//   WRITE       - BRAM write; status OK
//   PREFETCH    - prefetch_used=1, status OK (no actual data movement in MVP)
//   EVICT       - status OK (no actual eviction in MVP)
//   INVALIDATE  - status OK (no per-line invalidation in MVP)
//   QUERY_STATS - status OK, no memory access
//   RESET_STATS - status OK, signals stats reset upstream via mem_resp_stats_rst
//   PROGRAM_CONTRACT / RESET_CONTRACT - MVP returns OK; real programming
//                                      happens via AXI4-Lite shim
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_memory_engine
  import kvq_pkg::*;
#(
  parameter int MEM_LATENCY_CYCLES_MAX = 16
) (
  input  logic                            clk,
  input  logic                            rst_n,

  input  logic [7:0]                      cfg_mem_latency_cycles,
  input  logic                            cfg_clear_bram_valid,

  // From arbiter (selected request)
  input  logic                            in_valid,
  output logic                            in_ready,
  input  kvq_req_t                        in_req,
  input  logic [TENANT_IDX_WIDTH-1:0]     in_tenant_idx,
  input  logic [31:0]                     in_issue_tag,

  // Response handshake to response_builder
  output logic                            out_valid,
  input  logic                            out_ready,
  output kvq_req_t                        out_req,
  output logic [TENANT_IDX_WIDTH-1:0]     out_tenant_idx,
  output logic [31:0]                     out_issue_tag,
  output logic [7:0]                      out_status,
  output logic                            out_hit,
  output logic                            out_prefetch_used
);

  typedef enum logic [2:0] { S_IDLE, S_WAIT, S_ISSUE, S_LATCH, S_RESP } mem_state_e;
  mem_state_e state, nstate;

  kvq_req_t                  held_req;
  logic [TENANT_IDX_WIDTH-1:0] held_tenant;
  logic [31:0]                held_tag;
  logic [7:0]                 wait_cnt;
  logic [7:0]                 status_r;
  logic                       hit_r;
  logic                       prefetch_r;

  // BRAM port signals
  logic                       bram_we;
  logic                       bram_re;
  logic [BRAM_ADDR_WIDTH-1:0] bram_addr;
  logic [63:0]                bram_wdata;
  logic [63:0]                bram_rdata;
  logic                       bram_rvalid;
  logic                       bram_rhit;

  kvq_bram_model #(
    .ADDR_W(BRAM_ADDR_WIDTH),
    .DEPTH (BRAM_DEPTH),
    .DATA_W(64)
  ) u_bram (
    .clk             (clk),
    .rst_n           (rst_n),
    .we              (bram_we),
    .re              (bram_re),
    .addr            (bram_addr),
    .wdata           (bram_wdata),
    .clear_valid_bits(cfg_clear_bram_valid),
    .rdata           (bram_rdata),
    .rvalid          (bram_rvalid),
    .rhit            (bram_rhit)
  );

  assign in_ready = (state == S_IDLE);

  // Address mapping: take low BRAM_ADDR_WIDTH bits of kv_address
  wire [BRAM_ADDR_WIDTH-1:0] mapped_addr = held_req.kv_address[BRAM_ADDR_WIDTH-1:0];

  always_comb begin
    nstate    = state;
    bram_we   = 1'b0;
    bram_re   = 1'b0;
    bram_addr = mapped_addr;
    bram_wdata = held_req.kv_address[63:0]; // MVP: write address as data
    case (state)
      S_IDLE:  if (in_valid) nstate = (cfg_mem_latency_cycles == 0) ? S_ISSUE : S_WAIT;
      S_WAIT:  if (wait_cnt == cfg_mem_latency_cycles - 1) nstate = S_ISSUE;
      S_ISSUE: begin
        case (held_req.opcode)
          KVQ_OP_READ:  bram_re = 1'b1;
          KVQ_OP_WRITE: bram_we = 1'b1;
          default: ;
        endcase
        nstate = S_LATCH;
      end
      S_LATCH: nstate = S_RESP;
      S_RESP:  if (out_ready) nstate = S_IDLE;
      default: nstate = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= S_IDLE;
      held_req    <= '0;
      held_tenant <= '0;
      held_tag    <= '0;
      wait_cnt    <= '0;
      status_r    <= KVQ_STATUS_OK;
      hit_r       <= 1'b0;
      prefetch_r  <= 1'b0;
    end else begin
      state <= nstate;

      if (state == S_IDLE && in_valid) begin
        held_req    <= in_req;
        held_tenant <= in_tenant_idx;
        held_tag    <= in_issue_tag;
        wait_cnt    <= '0;
      end else if (state == S_WAIT) begin
        wait_cnt <= wait_cnt + 8'd1;
      end

      if (state == S_ISSUE) begin
        // Default
        hit_r      <= 1'b0;
        prefetch_r <= 1'b0;
        case (held_req.opcode)
          KVQ_OP_READ: begin
            // hit/miss known after BRAM register stage; we sample one cycle later
          end
          KVQ_OP_WRITE: begin
            status_r <= KVQ_STATUS_OK;
            hit_r    <= 1'b1;
          end
          KVQ_OP_PREFETCH: begin
            status_r   <= KVQ_STATUS_OK;
            prefetch_r <= 1'b1;
          end
          KVQ_OP_EVICT,
          KVQ_OP_INVALIDATE,
          KVQ_OP_QUERY_STATS,
          KVQ_OP_RESET_STATS,
          KVQ_OP_PROGRAM_CONTRACT,
          KVQ_OP_RESET_CONTRACT: begin
            status_r <= KVQ_STATUS_OK;
          end
          default: begin
            status_r <= KVQ_STATUS_ERR_BAD_OPCODE;
          end
        endcase
      end

      // Capture BRAM read result on the LATCH cycle (one cycle after S_ISSUE)
      if (state == S_LATCH && bram_rvalid && held_req.opcode == KVQ_OP_READ) begin
        hit_r    <= bram_rhit;
        status_r <= bram_rhit ? KVQ_STATUS_OK : KVQ_STATUS_MISS;
      end
    end
  end

  assign out_valid          = (state == S_RESP);
  assign out_req            = held_req;
  assign out_tenant_idx     = held_tenant;
  assign out_issue_tag      = held_tag;
  assign out_status         = status_r;
  assign out_hit            = hit_r;
  assign out_prefetch_used  = prefetch_r;

endmodule : kvq_memory_engine
