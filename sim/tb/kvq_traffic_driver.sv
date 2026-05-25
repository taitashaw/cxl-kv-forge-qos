// -----------------------------------------------------------------------------
// kvq_traffic_driver.sv
// Lightweight AXI4-Stream master that the testbench drives by call. Exposes
// tasks for single-beat request transmission with optional ready-stall
// pattern. Simulation-only.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_traffic_driver
  import kvq_pkg::*;
(
  input  logic                         clk,
  input  logic                         rst_n,
  output logic                         m_axis_tvalid,
  input  logic                         m_axis_tready,
  output logic [REQUEST_WIDTH-1:0]     m_axis_tdata,
  output logic                         m_axis_tlast
);

  initial begin
    m_axis_tvalid = 1'b0;
    m_axis_tdata  = '0;
    m_axis_tlast  = 1'b0;
  end

  task automatic drive_req(input logic [REQUEST_WIDTH-1:0] packet, input logic last_bit = 1'b1);
    @(posedge clk);
    m_axis_tdata  <= packet;
    m_axis_tvalid <= 1'b1;
    m_axis_tlast  <= last_bit;
    do @(posedge clk); while (!m_axis_tready);
    m_axis_tvalid <= 1'b0;
    m_axis_tlast  <= 1'b0;
  endtask

endmodule : kvq_traffic_driver
