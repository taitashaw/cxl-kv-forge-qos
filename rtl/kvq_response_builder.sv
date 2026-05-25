// -----------------------------------------------------------------------------
// kvq_response_builder.sv
// Packs a kvq_resp_t into the 256-bit AXIS response payload. Two input
// streams: the memory-engine result (normal path) and the error side-channel
// (parser/credit-engine/queue-manager errors). Memory-engine path has higher
// priority because it carries latency_tracker tags that must be drained.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_response_builder
  import kvq_pkg::*;
(
  input  logic                              clk,
  input  logic                              rst_n,

  // From memory engine (success/miss path)
  input  logic                              mem_valid,
  output logic                              mem_ready,
  input  kvq_req_t                          mem_req,
  input  logic [7:0]                        mem_status,
  input  logic                              mem_hit,
  input  logic                              mem_prefetch_used,
  input  logic [31:0]                       mem_latency_cycles,
  input  logic                              mem_deadline_miss,
  input  logic [31:0]                       mem_credit_snapshot,
  input  logic [15:0]                       mem_queue_occ_snapshot,

  // From error handler
  input  logic                              err_valid,
  output logic                              err_ready,
  input  kvq_req_t                          err_req,
  input  logic [7:0]                        err_status,
  input  logic [31:0]                       err_credit_snapshot,
  input  logic [15:0]                       err_queue_occ_snapshot,

  // AXIS master (response output)
  output logic                              m_axis_resp_tvalid,
  input  logic                              m_axis_resp_tready,
  output logic [RESPONSE_WIDTH-1:0]         m_axis_resp_tdata,
  output logic                              m_axis_resp_tlast
);

  // Priority: mem_valid wins to keep latency tags moving.
  logic        sel_mem;
  kvq_resp_t   resp;
  logic [RESPONSE_WIDTH-1:0] tdata_r;
  logic        tvalid_r;

  always_comb begin
    sel_mem = mem_valid;
    resp    = '0;
    if (sel_mem) begin
      resp.status                   = mem_status;
      resp.request_id               = mem_req.request_id;
      resp.tenant_id                = mem_req.tenant_id;
      resp.latency_cycles           = mem_latency_cycles;
      resp.deadline_miss            = mem_deadline_miss;
      resp.hit                      = mem_hit;
      resp.prefetch_used            = mem_prefetch_used;
      resp.error_code               = (mem_status >= KVQ_STATUS_ERR_BAD_OPCODE) ? mem_status : 8'h00;
      resp.queue_occupancy_snapshot = mem_queue_occ_snapshot;
      resp.credit_snapshot          = mem_credit_snapshot;
    end else begin
      resp.status                   = err_status;
      resp.request_id               = err_req.request_id;
      resp.tenant_id                = err_req.tenant_id;
      resp.latency_cycles           = 32'd0;
      resp.deadline_miss            = 1'b0;
      resp.hit                      = 1'b0;
      resp.prefetch_used            = 1'b0;
      resp.error_code               = err_status;
      resp.queue_occupancy_snapshot = err_queue_occ_snapshot;
      resp.credit_snapshot          = err_credit_snapshot;
    end
  end

  // Two-phase output register: handshake first drains tvalid; the next idle
  // cycle accepts the next mem_path/err_path packet. The 1-cycle bubble keeps
  // mem_engine.out_valid from being re-sampled into tdata_r on the same cycle
  // the AXIS handshake completes.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tdata_r  <= '0;
      tvalid_r <= 1'b0;
    end else if (m_axis_resp_tvalid && m_axis_resp_tready) begin
      tvalid_r <= 1'b0;
    end else if (!tvalid_r && (mem_valid || err_valid)) begin
      tdata_r  <= pack_resp(resp);
      tvalid_r <= 1'b1;
    end
  end

  // Producers can advance only on the cycle we latch their data.
  assign mem_ready = !tvalid_r;
  assign err_ready = !tvalid_r && !mem_valid;

  assign m_axis_resp_tvalid = tvalid_r;
  assign m_axis_resp_tdata  = tdata_r;
  assign m_axis_resp_tlast  = tvalid_r;

endmodule : kvq_response_builder
