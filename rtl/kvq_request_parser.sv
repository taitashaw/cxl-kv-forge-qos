// -----------------------------------------------------------------------------
// kvq_request_parser.sv
// Decodes the 256-bit AXI4-Stream request packet into a kvq_req_t struct and
// flags malformed packets (unknown opcode). Phase 1 expects single-beat
// packets: tlast must be asserted on every accepted beat; otherwise the
// downstream malformed_request counter increments.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_request_parser
  import kvq_pkg::*;
(
  input  logic                     clk,
  input  logic                     rst_n,

  // AXI4-Stream slave (request input)
  input  logic                     s_axis_req_tvalid,
  output logic                     s_axis_req_tready,
  input  logic [REQUEST_WIDTH-1:0] s_axis_req_tdata,
  input  logic                     s_axis_req_tlast,

  // Parsed request (master, valid/ready)
  output logic                     m_req_valid,
  input  logic                     m_req_ready,
  output kvq_req_t                 m_req,
  output logic                     m_bad_opcode,
  output logic                     m_bad_framing
);

  kvq_req_t parsed;
  logic     parsed_valid;
  (* keep = "true" *) logic bad_op_r;
  (* keep = "true" *) logic bad_frame_r;

  assign s_axis_req_tready = !parsed_valid || m_req_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      parsed_valid <= 1'b0;
      bad_op_r     <= 1'b0;
      bad_frame_r  <= 1'b0;
      parsed       <= '0;
    end else begin
      if (m_req_valid && m_req_ready) begin
        parsed_valid <= 1'b0;
        bad_op_r     <= 1'b0;
        bad_frame_r  <= 1'b0;
      end

      if (s_axis_req_tvalid && s_axis_req_tready) begin
        parsed       <= unpack_req(s_axis_req_tdata);
        parsed_valid <= 1'b1;
        bad_op_r     <= !is_known_opcode(s_axis_req_tdata[255:248]);
        bad_frame_r  <= !s_axis_req_tlast;
      end
    end
  end

  assign m_req_valid   = parsed_valid;
  assign m_req         = parsed;
  assign m_bad_opcode  = bad_op_r;
  assign m_bad_framing = bad_frame_r;

endmodule : kvq_request_parser
