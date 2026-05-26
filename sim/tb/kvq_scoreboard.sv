// -----------------------------------------------------------------------------
// kvq_scoreboard.sv
// Captures AXIS responses and exposes a small associative-array log keyed by
// request_id. The testbench can query expected vs. observed status, tenant_id,
// and hit/miss after each test.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"
`include "kvq_test_pkg.sv"

module kvq_scoreboard
  import kvq_pkg::*;
  import kvq_test_pkg::*;
(
  input  logic                          clk,
  input  logic                          rst_n,
  input  logic                          m_axis_resp_tvalid,
  input  logic                          m_axis_resp_tready,
  input  logic [RESPONSE_WIDTH-1:0]     m_axis_resp_tdata
);

  kvq_resp_t observed [logic [15:0]];
  int        n_observed = 0;
  int        n_dl_miss  = 0;
  int        n_err      = 0;

  always_ff @(posedge clk) begin
    if (rst_n && m_axis_resp_tvalid && m_axis_resp_tready) begin
      kvq_resp_t r;
      r = unpack_resp(m_axis_resp_tdata);
      observed[r.request_id] = r;
      n_observed++;
      if (r.deadline_miss) n_dl_miss++;
      if (r.status >= KVQ_STATUS_ERR_BAD_OPCODE) n_err++;
    end
  end

  function automatic logic seen(input logic [15:0] rid);
    return observed.exists(rid);
  endfunction

  function automatic kvq_resp_t get(input logic [15:0] rid);
    return observed[rid];
  endfunction

endmodule : kvq_scoreboard
