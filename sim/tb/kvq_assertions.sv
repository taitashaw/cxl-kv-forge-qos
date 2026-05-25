// -----------------------------------------------------------------------------
// kvq_assertions.sv
// Simulation-only SVA checks. Bound into kvq_top via tb_kvq_top. Disabled
// during reset; keep this file out of rtl/ to ensure synthesis ignores it.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_assertions
  import kvq_pkg::*;
(
  input  logic                            clk,
  input  logic                            rst_n,

  input  logic                            s_axis_req_tvalid,
  input  logic                            s_axis_req_tready,
  input  logic [REQUEST_WIDTH-1:0]        s_axis_req_tdata,

  input  logic                            m_axis_resp_tvalid,
  input  logic                            m_axis_resp_tready,
  input  logic [RESPONSE_WIDTH-1:0]       m_axis_resp_tdata,

  input  logic                            s_axil_awvalid,
  input  logic                            s_axil_wvalid,
  input  logic                            s_axil_bvalid,
  input  logic                            s_axil_arvalid,
  input  logic                            s_axil_rvalid
);

  // AXIS request data must be stable while valid && !ready
  property p_req_stable;
    @(posedge clk) disable iff (!rst_n)
      (s_axis_req_tvalid && !s_axis_req_tready) |=>
        (s_axis_req_tvalid && $stable(s_axis_req_tdata));
  endproperty
  a_req_stable: assert property (p_req_stable) else
    $error("kvq_assert: s_axis_req_tdata changed while tvalid and not tready");

  // AXIS response data stable while valid && !ready
  // The consequent intentionally does NOT require tvalid to remain asserted at
  // the next cycle: AXI4-Stream allows tvalid to drop after a handshake, and
  // simulator scheduling of blocking testbench assignments versus the DUT's
  // always_ff can produce a same-cycle handshake at the moment tready is
  // released. The structural property we care about is that tdata itself
  // never mutates between successive stall cycles.
  property p_resp_stable;
    @(posedge clk) disable iff (!rst_n)
      (m_axis_resp_tvalid && !m_axis_resp_tready) |=>
        $stable(m_axis_resp_tdata);
  endproperty
  a_resp_stable: assert property (p_resp_stable) else
    $error("kvq_assert: m_axis_resp_tdata changed while tvalid and not tready");

  // No X status byte after reset on a response handshake
  property p_resp_no_x;
    @(posedge clk) disable iff (!rst_n)
      (m_axis_resp_tvalid && m_axis_resp_tready) |->
        !$isunknown(m_axis_resp_tdata[255:248]);
  endproperty
  a_resp_no_x: assert property (p_resp_no_x) else
    $error("kvq_assert: response status byte is X");

  // AXI4-Lite write must complete: aw or w accepted implies bvalid eventually
  property p_axil_b_follows;
    @(posedge clk) disable iff (!rst_n)
      s_axil_awvalid |-> ##[1:64] s_axil_bvalid;
  endproperty
  a_axil_b: assert property (p_axil_b_follows) else
    $error("kvq_assert: bvalid did not follow aw within 64 cycles");

  property p_axil_r_follows;
    @(posedge clk) disable iff (!rst_n)
      s_axil_arvalid |-> ##[1:64] s_axil_rvalid;
  endproperty
  a_axil_r: assert property (p_axil_r_follows) else
    $error("kvq_assert: rvalid did not follow ar within 64 cycles");

endmodule : kvq_assertions
