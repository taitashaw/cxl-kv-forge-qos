// -----------------------------------------------------------------------------
// kvq_top.sv
// CXL-KV Forge-QoS - Phase 1 top-level integration.
//
// Pipeline:
//   AXIS req
//     -> kvq_request_parser
//     -> kvq_tenant_contract_table (combinational lookup)
//     -> kvq_credit_engine          (good path / error side-channel)
//     -> kvq_per_tenant_queue_manager
//     -> kvq_deadline_arbiter
//     -> kvq_latency_tracker (tag issue)
//     -> kvq_memory_engine -> kvq_bram_model
//     -> kvq_response_builder
//     -> AXIS resp
//   kvq_error_handler funnels parser/credit/queue errors into resp_builder.
//   kvq_axil_regs handles control/status/counter/contract programming.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_top
  import kvq_pkg::*;
(
  input  logic                         clk,
  input  logic                         rst_n,

  // AXI4-Stream request input
  input  logic                         s_axis_req_tvalid,
  output logic                         s_axis_req_tready,
  input  logic [REQUEST_WIDTH-1:0]     s_axis_req_tdata,
  input  logic                         s_axis_req_tlast,

  // AXI4-Stream response output
  output logic                         m_axis_resp_tvalid,
  input  logic                         m_axis_resp_tready,
  output logic [RESPONSE_WIDTH-1:0]    m_axis_resp_tdata,
  output logic                         m_axis_resp_tlast,

  // Simplified AXI4-Lite
  input  logic                         s_axil_awvalid,
  output logic                         s_axil_awready,
  input  logic [15:0]                  s_axil_awaddr,
  input  logic                         s_axil_wvalid,
  output logic                         s_axil_wready,
  input  logic [31:0]                  s_axil_wdata,
  input  logic [3:0]                   s_axil_wstrb,
  output logic                         s_axil_bvalid,
  input  logic                         s_axil_bready,
  output logic [1:0]                   s_axil_bresp,
  input  logic                         s_axil_arvalid,
  output logic                         s_axil_arready,
  input  logic [15:0]                  s_axil_araddr,
  output logic                         s_axil_rvalid,
  input  logic                         s_axil_rready,
  output logic [31:0]                  s_axil_rdata,
  output logic [1:0]                   s_axil_rresp,

  // Debug / status
  output logic                         error_seen,
  output logic                         queue_full,
  output logic                         deadline_miss_seen,
  output logic [7:0]                   active_tenant_count,
  output logic [15:0]                  global_queue_occupancy
);

  // ---------------------------------------------------------------------------
  // Parser
  // ---------------------------------------------------------------------------
  logic     parser_out_valid;
  logic     parser_out_ready;
  kvq_req_t parser_out_req;
  logic     parser_bad_op;
  logic     parser_bad_frame;

  kvq_request_parser u_parser (
    .clk              (clk),
    .rst_n            (rst_n),
    .s_axis_req_tvalid(s_axis_req_tvalid),
    .s_axis_req_tready(s_axis_req_tready),
    .s_axis_req_tdata (s_axis_req_tdata),
    .s_axis_req_tlast (s_axis_req_tlast),
    .m_req_valid      (parser_out_valid),
    .m_req_ready      (parser_out_ready),
    .m_req            (parser_out_req),
    .m_bad_opcode     (parser_bad_op),
    .m_bad_framing    (parser_bad_frame)
  );

  // ---------------------------------------------------------------------------
  // Contract table
  // ---------------------------------------------------------------------------
  kvq_contract_t lookup_contract;
  logic          lookup_valid_unused;
  logic          cfg_write;
  logic [TENANT_IDX_WIDTH-1:0] cfg_tenant_idx;
  logic [3:0]                  cfg_field_sel;
  logic [31:0]                 cfg_wdata;
  logic                        cfg_reset_all;

  kvq_tenant_contract_table u_contract (
    .clk                 (clk),
    .rst_n               (rst_n),
    .cfg_write           (cfg_write),
    .cfg_tenant_idx      (cfg_tenant_idx),
    .cfg_field_sel       (cfg_field_sel),
    .cfg_wdata           (cfg_wdata),
    .cfg_reset_all       (cfg_reset_all),
    .lookup_tenant_id    (parser_out_req.tenant_id),
    .lookup_contract     (lookup_contract),
    .lookup_valid        (lookup_valid_unused),
    .active_tenant_count (active_tenant_count)
  );

  // ---------------------------------------------------------------------------
  // Credit engine
  // ---------------------------------------------------------------------------
  logic     ce_out_valid;
  logic     ce_out_ready;
  kvq_req_t ce_out_req;
  logic     ce_err_valid;
  logic     ce_err_ready;
  kvq_req_t ce_err_req;
  logic [7:0] ce_err_status;
  logic [31:0] credit_snapshot;
  logic        credit_starvation_pulse;

  kvq_credit_engine u_credit (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .req_tenant_id          (parser_out_req.tenant_id),
    .req_contract           (lookup_contract),
    .in_valid               (parser_out_valid),
    .in_ready               (parser_out_ready),
    .in_req                 (parser_out_req),
    .in_bad_opcode          (parser_bad_op),
    .in_bad_framing         (parser_bad_frame),
    .out_valid              (ce_out_valid),
    .out_ready              (ce_out_ready),
    .out_req                (ce_out_req),
    .err_valid              (ce_err_valid),
    .err_ready              (ce_err_ready),
    .err_req                (ce_err_req),
    .err_status             (ce_err_status),
    .credit_snapshot        (credit_snapshot),
    .credit_starvation_pulse(credit_starvation_pulse)
  );

  // ---------------------------------------------------------------------------
  // Queue manager
  // ---------------------------------------------------------------------------
  logic                    qm_full_err_valid;
  kvq_req_t                qm_full_err_req;
  logic [MAX_TENANTS-1:0]  qm_deq_valid;
  kvq_req_t                qm_deq_req       [0:MAX_TENANTS-1];
  logic [MAX_TENANTS-1:0]  arb_deq_grant;
  logic [QUEUE_OCC_WIDTH-1:0] per_tenant_occ [0:MAX_TENANTS-1];
  logic                    soft_reset;

  kvq_per_tenant_queue_manager u_qmgr (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .soft_reset            (soft_reset),
    .enq_valid             (ce_out_valid),
    .enq_ready             (ce_out_ready),
    .enq_req               (ce_out_req),
    .enq_max_depth         (lookup_contract.max_queue_depth),
    .full_err_valid        (qm_full_err_valid),
    .full_err_req          (qm_full_err_req),
    .deq_valid             (qm_deq_valid),
    .deq_req               (qm_deq_req),
    .deq_grant             (arb_deq_grant),
    .global_queue_occupancy(global_queue_occupancy),
    .per_tenant_occupancy  (per_tenant_occ),
    .queue_full            (queue_full)
  );

  // ---------------------------------------------------------------------------
  // Deadline arbiter
  // ---------------------------------------------------------------------------
  logic                       arb_sel_valid;
  logic                       arb_sel_ready;
  kvq_req_t                   arb_sel_req;
  logic [TENANT_IDX_WIDTH-1:0] arb_sel_tenant_idx;

  kvq_deadline_arbiter u_arb (
    .clk           (clk),
    .rst_n         (rst_n),
    .deq_valid     (qm_deq_valid),
    .deq_req       (qm_deq_req),
    .deq_grant     (arb_deq_grant),
    .sel_valid     (arb_sel_valid),
    .sel_ready     (arb_sel_ready),
    .sel_req       (arb_sel_req),
    .sel_tenant_idx(arb_sel_tenant_idx)
  );

  // ---------------------------------------------------------------------------
  // Latency tracker
  // ---------------------------------------------------------------------------
  logic [31:0] lt_issue_tag;
  logic [31:0] lt_complete_tag;
  logic [31:0] lt_complete_deadline;
  logic [31:0] lt_complete_latency;
  logic        lt_complete_deadline_miss;
  logic [31:0] cycle_counter;

  kvq_latency_tracker u_lt (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .soft_reset            (soft_reset),
    .issue_valid           (arb_sel_valid && arb_sel_ready),
    .issue_tag             (lt_issue_tag),
    .complete_tag          (lt_complete_tag),
    .complete_deadline     (lt_complete_deadline),
    .complete_latency      (lt_complete_latency),
    .complete_deadline_miss(lt_complete_deadline_miss),
    .cycle_counter         (cycle_counter)
  );

  // ---------------------------------------------------------------------------
  // Memory engine + BRAM
  // ---------------------------------------------------------------------------
  logic                       me_out_valid;
  logic                       me_out_ready;
  kvq_req_t                   me_out_req;
  logic [TENANT_IDX_WIDTH-1:0] me_out_tenant;
  logic [31:0]                me_out_tag;
  logic [7:0]                 me_out_status;
  logic                       me_out_hit;
  logic                       me_out_prefetch;
  logic [7:0]                 cfg_mem_latency_cycles;

  kvq_memory_engine #(
    .MEM_LATENCY_CYCLES_MAX(16)
  ) u_mem (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .cfg_mem_latency_cycles (cfg_mem_latency_cycles),
    .cfg_clear_bram_valid   (soft_reset),
    .in_valid               (arb_sel_valid),
    .in_ready               (arb_sel_ready),
    .in_req                 (arb_sel_req),
    .in_tenant_idx          (arb_sel_tenant_idx),
    .in_issue_tag           (lt_issue_tag),
    .out_valid              (me_out_valid),
    .out_ready              (me_out_ready),
    .out_req                (me_out_req),
    .out_tenant_idx         (me_out_tenant),
    .out_issue_tag          (me_out_tag),
    .out_status             (me_out_status),
    .out_hit                (me_out_hit),
    .out_prefetch_used      (me_out_prefetch)
  );

  // Latency calc connect-through
  assign lt_complete_tag      = me_out_tag;
  assign lt_complete_deadline = me_out_req.deadline_cycles;

  // ---------------------------------------------------------------------------
  // Error handler
  // ---------------------------------------------------------------------------
  logic     err_resp_valid;
  logic     err_resp_ready;
  kvq_req_t err_resp_req;
  logic [7:0] err_resp_status;

  kvq_error_handler u_err (
    .clk          (clk),
    .rst_n        (rst_n),
    .ce_err_valid (ce_err_valid),
    .ce_err_ready (ce_err_ready),
    .ce_err_req   (ce_err_req),
    .ce_err_status(ce_err_status),
    .qm_full_valid(qm_full_err_valid),
    .qm_full_req  (qm_full_err_req),
    .err_valid    (err_resp_valid),
    .err_ready    (err_resp_ready),
    .err_req      (err_resp_req),
    .err_status   (err_resp_status)
  );

  // ---------------------------------------------------------------------------
  // Response builder
  // ---------------------------------------------------------------------------
  kvq_response_builder u_resp (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .mem_valid              (me_out_valid),
    .mem_ready              (me_out_ready),
    .mem_req                (me_out_req),
    .mem_status             (me_out_status),
    .mem_hit                (me_out_hit),
    .mem_prefetch_used      (me_out_prefetch),
    .mem_latency_cycles     (lt_complete_latency),
    .mem_deadline_miss      (lt_complete_deadline_miss),
    .mem_credit_snapshot    (credit_snapshot),
    .mem_queue_occ_snapshot (global_queue_occupancy),
    .err_valid              (err_resp_valid),
    .err_ready              (err_resp_ready),
    .err_req                (err_resp_req),
    .err_status             (err_resp_status),
    .err_credit_snapshot    (credit_snapshot),
    .err_queue_occ_snapshot (global_queue_occupancy),
    .m_axis_resp_tvalid     (m_axis_resp_tvalid),
    .m_axis_resp_tready     (m_axis_resp_tready),
    .m_axis_resp_tdata      (m_axis_resp_tdata),
    .m_axis_resp_tlast      (m_axis_resp_tlast)
  );

  // ---------------------------------------------------------------------------
  // SLA monitor + perf counters
  // ---------------------------------------------------------------------------
  logic ev_req_accepted;
  logic ev_response_emitted;
  logic ev_malformed;
  logic ev_in_backpressure;
  logic ev_out_backpressure;

  assign ev_req_accepted     = ce_out_valid && ce_out_ready;
  assign ev_response_emitted = m_axis_resp_tvalid && m_axis_resp_tready;
  assign ev_malformed        = parser_out_valid && (parser_bad_op || parser_bad_frame);
  assign ev_in_backpressure  = s_axis_req_tvalid && !s_axis_req_tready;
  assign ev_out_backpressure = m_axis_resp_tvalid && !m_axis_resp_tready;

  logic [31:0] cnt_total_requests;
  logic [31:0] cnt_read_requests;
  logic [31:0] cnt_write_requests;
  logic [31:0] cnt_prefetch_requests;
  logic [31:0] cnt_deadline_miss;
  logic [31:0] cnt_credit_starvation;
  logic [31:0] cnt_malformed_request;
  logic [31:0] cnt_input_backpressure;
  logic [31:0] cnt_output_backpressure;
  logic [31:0] cnt_max_latency;
  logic [31:0] cnt_cumulative_latency;
  logic [15:0] cnt_max_queue_occupancy;
  logic        counter_reset;

  kvq_sla_monitor u_sla (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .counter_reset          (counter_reset),
    .ev_req_accepted        (ev_req_accepted),
    .ev_req_opcode          (ce_out_req.opcode),
    .ev_response_emitted    (ev_response_emitted),
    .ev_deadline_miss       (ev_response_emitted && lt_complete_deadline_miss),
    .ev_credit_starvation   (credit_starvation_pulse),
    .ev_malformed_request   (ev_malformed),
    .ev_in_backpressure     (ev_in_backpressure),
    .ev_out_backpressure    (ev_out_backpressure),
    .ev_latency_cycles      (lt_complete_latency),
    .ev_queue_occupancy     (global_queue_occupancy),
    .cnt_total_requests     (cnt_total_requests),
    .cnt_read_requests      (cnt_read_requests),
    .cnt_write_requests     (cnt_write_requests),
    .cnt_prefetch_requests  (cnt_prefetch_requests),
    .cnt_deadline_miss      (cnt_deadline_miss),
    .cnt_credit_starvation  (cnt_credit_starvation),
    .cnt_malformed_request  (cnt_malformed_request),
    .cnt_input_backpressure (cnt_input_backpressure),
    .cnt_output_backpressure(cnt_output_backpressure),
    .cnt_max_latency        (cnt_max_latency),
    .cnt_cumulative_latency (cnt_cumulative_latency),
    .cnt_max_queue_occupancy(cnt_max_queue_occupancy)
  );

  logic [3:0]  cnt_sel;
  logic [31:0] cnt_data;
  kvq_perf_counters u_perf (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .cnt_total_requests     (cnt_total_requests),
    .cnt_read_requests      (cnt_read_requests),
    .cnt_write_requests     (cnt_write_requests),
    .cnt_prefetch_requests  (cnt_prefetch_requests),
    .cnt_deadline_miss      (cnt_deadline_miss),
    .cnt_credit_starvation  (cnt_credit_starvation),
    .cnt_malformed_request  (cnt_malformed_request),
    .cnt_input_backpressure (cnt_input_backpressure),
    .cnt_output_backpressure(cnt_output_backpressure),
    .cnt_max_latency        (cnt_max_latency),
    .cnt_cumulative_latency (cnt_cumulative_latency),
    .cnt_max_queue_occupancy(cnt_max_queue_occupancy),
    .rb_sel                 (cnt_sel),
    .rb_data                (cnt_data)
  );

  // ---------------------------------------------------------------------------
  // Sticky status flags
  // ---------------------------------------------------------------------------
  logic err_seen_r;
  logic dl_miss_seen_r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || counter_reset) begin
      err_seen_r     <= 1'b0;
      dl_miss_seen_r <= 1'b0;
    end else begin
      if (err_resp_valid && err_resp_ready) err_seen_r <= 1'b1;
      if (ev_response_emitted && lt_complete_deadline_miss) dl_miss_seen_r <= 1'b1;
    end
  end
  assign error_seen          = err_seen_r;
  assign deadline_miss_seen  = dl_miss_seen_r;

  // ---------------------------------------------------------------------------
  // Debug nets exposed via MARK_DEBUG. The post-synth debug-core insertion
  // step in synth_impl_bitstream.tcl finds these and attaches them to an
  // ILA, producing the .ltx file for HW Manager. Keeping them internal
  // (no top-level ports) avoids critical-warning conflicts with IPI's bus
  // interface inference on the AXIS ports.
  // ---------------------------------------------------------------------------
  (* mark_debug = "true" *) logic [TENANT_IDX_WIDTH-1:0] dbg_arb_sel_tenant_idx;
  (* mark_debug = "true" *) logic                       dbg_arb_sel_valid;
  (* mark_debug = "true" *) logic [31:0]                dbg_credit_snapshot;
  (* mark_debug = "true" *) logic                       dbg_credit_starvation_pulse;
  (* mark_debug = "true" *) logic                       dbg_refill_pulse;
  (* mark_debug = "true" *) logic [31:0]                dbg_latency_cycles;
  (* mark_debug = "true" *) logic                       dbg_deadline_miss;
  (* mark_debug = "true" *) logic [MAX_TENANTS*QUEUE_OCC_WIDTH-1:0] dbg_per_tenant_occupancy_flat;

  assign dbg_arb_sel_tenant_idx      = arb_sel_tenant_idx;
  assign dbg_arb_sel_valid           = arb_sel_valid;
  assign dbg_credit_snapshot         = credit_snapshot;
  assign dbg_credit_starvation_pulse = credit_starvation_pulse;
  assign dbg_refill_pulse            = u_credit.refill_pulse;
  assign dbg_latency_cycles          = lt_complete_latency;
  assign dbg_deadline_miss           = lt_complete_deadline_miss;

  genvar g_dbg;
  generate
    for (g_dbg = 0; g_dbg < MAX_TENANTS; g_dbg++) begin : g_dbg_occ
      assign dbg_per_tenant_occupancy_flat[
        g_dbg*QUEUE_OCC_WIDTH +: QUEUE_OCC_WIDTH
      ] = per_tenant_occ[g_dbg];
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // AXI4-Lite register file
  // ---------------------------------------------------------------------------
  logic ctl_enable_unused;
  logic ctl_qos_enable_unused;

  kvq_axil_regs u_axil (
    .clk                       (clk),
    .rst_n                     (rst_n),
    .s_axil_awvalid            (s_axil_awvalid),
    .s_axil_awready            (s_axil_awready),
    .s_axil_awaddr             (s_axil_awaddr),
    .s_axil_wvalid             (s_axil_wvalid),
    .s_axil_wready             (s_axil_wready),
    .s_axil_wdata              (s_axil_wdata),
    .s_axil_wstrb              (s_axil_wstrb),
    .s_axil_bvalid             (s_axil_bvalid),
    .s_axil_bready             (s_axil_bready),
    .s_axil_bresp              (s_axil_bresp),
    .s_axil_arvalid            (s_axil_arvalid),
    .s_axil_arready            (s_axil_arready),
    .s_axil_araddr             (s_axil_araddr),
    .s_axil_rvalid             (s_axil_rvalid),
    .s_axil_rready             (s_axil_rready),
    .s_axil_rdata              (s_axil_rdata),
    .s_axil_rresp              (s_axil_rresp),
    .ctl_enable                (ctl_enable_unused),
    .ctl_soft_reset            (soft_reset),
    .ctl_counter_reset         (counter_reset),
    .ctl_qos_enable            (ctl_qos_enable_unused),
    .ctl_memory_latency_cycles (cfg_mem_latency_cycles),
    .sts_error_seen            (error_seen),
    .sts_queue_full            (queue_full),
    .sts_deadline_miss_seen    (deadline_miss_seen),
    .sts_active_tenant_count   (active_tenant_count),
    .sts_global_queue_occupancy(global_queue_occupancy),
    .cnt_sel                   (cnt_sel),
    .cnt_data                  (cnt_data),
    .cfg_write                 (cfg_write),
    .cfg_tenant_idx            (cfg_tenant_idx),
    .cfg_field_sel             (cfg_field_sel),
    .cfg_wdata                 (cfg_wdata),
    .cfg_reset_all             (cfg_reset_all)
  );

endmodule : kvq_top
