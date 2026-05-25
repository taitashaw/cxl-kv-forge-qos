// -----------------------------------------------------------------------------
// kvq_top_bd_wrap.v
//
// Verilog wrapper around the SystemVerilog kvq_top module so Vivado IP
// Integrator can reference it as a BD module (IPI rejects SystemVerilog
// modules as the top file of a module reference).
//
// AXI4-Lite port-name translation: kvq_top names its slave-side AXI4-Lite
// ports s_axil_aw*/w*/b*/ar*/r*. Vivado IPI infers AXI4-Lite from the
// canonical prefix s_axi_lite_; this wrapper renames on the way in so
// IPI auto-creates the s_axi_lite bus interface for smartconnect.
//
// Internal kvq_top debug nets are tagged with MARK_DEBUG in RTL; the
// synth_impl_bitstream.tcl flow inserts a post-synth ILA on those nets
// and writes the .ltx file for HW Manager. This wrapper therefore does
// NOT expose dbg_* outputs - keeping them out of the BD boundary avoids
// IPI bus-inference conflicts.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module kvq_top_bd_wrap (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         s_axis_req_tvalid,
  output wire         s_axis_req_tready,
  input  wire [255:0] s_axis_req_tdata,
  input  wire         s_axis_req_tlast,

  output wire         m_axis_resp_tvalid,
  input  wire         m_axis_resp_tready,
  output wire [255:0] m_axis_resp_tdata,
  output wire         m_axis_resp_tlast,

  input  wire         s_axi_lite_awvalid,
  output wire         s_axi_lite_awready,
  input  wire [15:0]  s_axi_lite_awaddr,
  input  wire         s_axi_lite_wvalid,
  output wire         s_axi_lite_wready,
  input  wire [31:0]  s_axi_lite_wdata,
  input  wire [3:0]   s_axi_lite_wstrb,
  output wire         s_axi_lite_bvalid,
  input  wire         s_axi_lite_bready,
  output wire [1:0]   s_axi_lite_bresp,
  input  wire         s_axi_lite_arvalid,
  output wire         s_axi_lite_arready,
  input  wire [15:0]  s_axi_lite_araddr,
  output wire         s_axi_lite_rvalid,
  input  wire         s_axi_lite_rready,
  output wire [31:0]  s_axi_lite_rdata,
  output wire [1:0]   s_axi_lite_rresp,

  output wire         error_seen,
  output wire         queue_full,
  output wire         deadline_miss_seen,
  output wire [7:0]   active_tenant_count,
  output wire [15:0]  global_queue_occupancy
);

  kvq_top u_kvq_top (
    .clk                          (clk),
    .rst_n                        (rst_n),
    .s_axis_req_tvalid            (s_axis_req_tvalid),
    .s_axis_req_tready            (s_axis_req_tready),
    .s_axis_req_tdata             (s_axis_req_tdata),
    .s_axis_req_tlast             (s_axis_req_tlast),
    .m_axis_resp_tvalid           (m_axis_resp_tvalid),
    .m_axis_resp_tready           (m_axis_resp_tready),
    .m_axis_resp_tdata            (m_axis_resp_tdata),
    .m_axis_resp_tlast            (m_axis_resp_tlast),
    .s_axil_awvalid               (s_axi_lite_awvalid),
    .s_axil_awready               (s_axi_lite_awready),
    .s_axil_awaddr                (s_axi_lite_awaddr),
    .s_axil_wvalid                (s_axi_lite_wvalid),
    .s_axil_wready                (s_axi_lite_wready),
    .s_axil_wdata                 (s_axi_lite_wdata),
    .s_axil_wstrb                 (s_axi_lite_wstrb),
    .s_axil_bvalid                (s_axi_lite_bvalid),
    .s_axil_bready                (s_axi_lite_bready),
    .s_axil_bresp                 (s_axi_lite_bresp),
    .s_axil_arvalid               (s_axi_lite_arvalid),
    .s_axil_arready               (s_axi_lite_arready),
    .s_axil_araddr                (s_axi_lite_araddr),
    .s_axil_rvalid                (s_axi_lite_rvalid),
    .s_axil_rready                (s_axi_lite_rready),
    .s_axil_rdata                 (s_axi_lite_rdata),
    .s_axil_rresp                 (s_axi_lite_rresp),
    .error_seen                   (error_seen),
    .queue_full                   (queue_full),
    .deadline_miss_seen           (deadline_miss_seen),
    .active_tenant_count          (active_tenant_count),
    .global_queue_occupancy       (global_queue_occupancy)
  );

endmodule
