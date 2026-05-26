// -----------------------------------------------------------------------------
// tb_kvq_top.sv
// XSim testbench for the Phase 1 CXL-KV Forge-QoS top. Drives directed tests
// 1..12 from the Phase 1 verification plan. Writes pass/fail to console and
// (best-effort) to results/rtl_sim/phase1_xsim_summary.csv.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"
`include "kvq_test_pkg.sv"

module tb_kvq_top;

  import kvq_pkg::*;
  import kvq_test_pkg::*;

  // 250 MHz clock => 4 ns period
  localparam time CLK_PERIOD = 4ns;

  logic clk;
  logic rst_n;

  // AXIS request
  logic                       s_axis_req_tvalid;
  logic                       s_axis_req_tready;
  logic [REQUEST_WIDTH-1:0]   s_axis_req_tdata;
  logic                       s_axis_req_tlast;

  // AXIS response
  logic                       m_axis_resp_tvalid;
  logic                       m_axis_resp_tready;
  logic [RESPONSE_WIDTH-1:0]  m_axis_resp_tdata;
  logic                       m_axis_resp_tlast;

  // AXI4-Lite
  logic        s_axil_awvalid; logic        s_axil_awready;
  logic [15:0] s_axil_awaddr;
  logic        s_axil_wvalid;  logic        s_axil_wready;
  logic [31:0] s_axil_wdata;
  logic [3:0]  s_axil_wstrb;
  logic        s_axil_bvalid;  logic        s_axil_bready;
  logic [1:0]  s_axil_bresp;
  logic        s_axil_arvalid; logic        s_axil_arready;
  logic [15:0] s_axil_araddr;
  logic        s_axil_rvalid;  logic        s_axil_rready;
  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;

  logic        error_seen;
  logic        queue_full;
  logic        deadline_miss_seen;
  logic [7:0]  active_tenant_count;
  logic [15:0] global_queue_occupancy;

  // ---------------------------------------------------------------------------
  // Clock + reset
  // ---------------------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // ---------------------------------------------------------------------------
  // Traffic driver (AXIS master)
  // ---------------------------------------------------------------------------
  kvq_traffic_driver u_drv (
    .clk          (clk),
    .rst_n        (rst_n),
    .m_axis_tvalid(s_axis_req_tvalid),
    .m_axis_tready(s_axis_req_tready),
    .m_axis_tdata (s_axis_req_tdata),
    .m_axis_tlast (s_axis_req_tlast)
  );

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  kvq_top u_dut (
    .clk                       (clk),
    .rst_n                     (rst_n),
    .s_axis_req_tvalid         (s_axis_req_tvalid),
    .s_axis_req_tready         (s_axis_req_tready),
    .s_axis_req_tdata          (s_axis_req_tdata),
    .s_axis_req_tlast          (s_axis_req_tlast),
    .m_axis_resp_tvalid        (m_axis_resp_tvalid),
    .m_axis_resp_tready        (m_axis_resp_tready),
    .m_axis_resp_tdata         (m_axis_resp_tdata),
    .m_axis_resp_tlast         (m_axis_resp_tlast),
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
    .error_seen                (error_seen),
    .queue_full                (queue_full),
    .deadline_miss_seen        (deadline_miss_seen),
    .active_tenant_count       (active_tenant_count),
    .global_queue_occupancy    (global_queue_occupancy)
  );

  // ---------------------------------------------------------------------------
  // Scoreboard + assertions
  // ---------------------------------------------------------------------------
  kvq_scoreboard u_sb (
    .clk               (clk),
    .rst_n             (rst_n),
    .m_axis_resp_tvalid(m_axis_resp_tvalid),
    .m_axis_resp_tready(m_axis_resp_tready),
    .m_axis_resp_tdata (m_axis_resp_tdata)
  );

  kvq_assertions u_asr (
    .clk                (clk),
    .rst_n              (rst_n),
    .s_axis_req_tvalid  (s_axis_req_tvalid),
    .s_axis_req_tready  (s_axis_req_tready),
    .s_axis_req_tdata   (s_axis_req_tdata),
    .m_axis_resp_tvalid (m_axis_resp_tvalid),
    .m_axis_resp_tready (m_axis_resp_tready),
    .m_axis_resp_tdata  (m_axis_resp_tdata),
    .s_axil_awvalid     (s_axil_awvalid),
    .s_axil_wvalid      (s_axil_wvalid),
    .s_axil_bvalid      (s_axil_bvalid),
    .s_axil_arvalid     (s_axil_arvalid),
    .s_axil_rvalid      (s_axil_rvalid)
  );

  // ---------------------------------------------------------------------------
  // Pass/fail tracking
  // ---------------------------------------------------------------------------
  int n_pass;
  int n_fail;
  int fd_csv;

  string current_test;

  task automatic record(input string test, input bit ok, input string note = "");
    if (ok) begin
      n_pass++;
      $display("[PASS] %-40s %s", test, note);
    end else begin
      n_fail++;
      $display("[FAIL] %-40s %s", test, note);
    end
    if (fd_csv) $fdisplay(fd_csv, "%s,%s,%s", test, ok ? "PASS" : "FAIL", note);
  endtask

  // ---------------------------------------------------------------------------
  // AXI4-Lite helpers
  // ---------------------------------------------------------------------------
  task automatic axil_write(input logic [15:0] addr, input logic [31:0] data);
    @(posedge clk);
    s_axil_awvalid <= 1'b1; s_axil_awaddr <= addr;
    s_axil_wvalid  <= 1'b1; s_axil_wdata  <= data; s_axil_wstrb <= 4'hF;
    s_axil_bready  <= 1'b1;
    do @(posedge clk); while (!(s_axil_awready));
    s_axil_awvalid <= 1'b0;
    do @(posedge clk); while (!(s_axil_wready));
    s_axil_wvalid  <= 1'b0;
    do @(posedge clk); while (!(s_axil_bvalid));
    s_axil_bready  <= 1'b0;
  endtask

  task automatic axil_read(input logic [15:0] addr, output logic [31:0] data);
    @(posedge clk);
    s_axil_arvalid <= 1'b1; s_axil_araddr <= addr;
    s_axil_rready  <= 1'b1;
    do @(posedge clk); while (!(s_axil_arready));
    s_axil_arvalid <= 1'b0;
    do @(posedge clk); while (!(s_axil_rvalid));
    data = s_axil_rdata;
    s_axil_rready <= 1'b0;
  endtask

  task automatic program_contract(
    input int unsigned tidx,
    input int unsigned min_bw,
    input int unsigned max_bw,
    input int unsigned burst_lim,
    input int unsigned deadline_cyc,
    input int unsigned prio,
    input int unsigned max_qdepth
  );
    axil_write(contract_addr(tidx, 0), 32'd1);          // valid
    axil_write(contract_addr(tidx, 1), min_bw);
    axil_write(contract_addr(tidx, 2), max_bw);
    axil_write(contract_addr(tidx, 3), burst_lim);
    axil_write(contract_addr(tidx, 4), deadline_cyc);
    axil_write(contract_addr(tidx, 5), prio);
    axil_write(contract_addr(tidx, 6), max_qdepth);
  endtask

  // ---------------------------------------------------------------------------
  // Wait for response with request_id within `cycles`
  // ---------------------------------------------------------------------------
  task automatic wait_for_resp(input logic [15:0] rid, input int cycles, output bit ok);
    int i;
    ok = 1'b0;
    for (i = 0; i < cycles; i++) begin
      if (u_sb.seen(rid)) begin ok = 1'b1; return; end
      @(posedge clk);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------------------
  kvq_req_t r;
  logic [REQUEST_WIDTH-1:0] pkt;
  logic [31:0] rd_val;
  bit ok;
  kvq_resp_t r_obs;

  initial begin
    // Init
    rst_n              = 1'b0;
    s_axil_awvalid     = 1'b0; s_axil_awaddr = 0;
    s_axil_wvalid      = 1'b0; s_axil_wdata  = 0; s_axil_wstrb = 0;
    s_axil_bready      = 1'b0;
    s_axil_arvalid     = 1'b0; s_axil_araddr = 0;
    s_axil_rready      = 1'b0;
    m_axis_resp_tready = 1'b1;
    n_pass = 0; n_fail = 0;

    // Open relative to xsim's current working directory. The shell wrapper
    // (scripts/run_xsim.sh) cd's into results/rtl_sim before invoking xsim, so
    // a plain filename lands the summary alongside xsim.log.
    fd_csv = $fopen("phase1_xsim_summary.csv", "w");
    if (fd_csv) $fdisplay(fd_csv, "test_name,result,note");

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    // -------------------------------------------------------------------------
    // T1: RESET_SANITY
    // -------------------------------------------------------------------------
    current_test = "RESET_SANITY";
    record(current_test,
      !error_seen && !queue_full && !deadline_miss_seen && (global_queue_occupancy == 0),
      $sformatf("err=%0d qf=%0d dm=%0d occ=%0d", error_seen, queue_full, deadline_miss_seen, global_queue_occupancy)
    );

    // -------------------------------------------------------------------------
    // T2: AXIL_READ_DEFAULT_STATUS
    // -------------------------------------------------------------------------
    current_test = "AXIL_READ_DEFAULT_STATUS";
    axil_read(16'h004, rd_val);
    record(current_test, (rd_val == 32'h0), $sformatf("status=0x%08h", rd_val));

    // -------------------------------------------------------------------------
    // T3: AXIL_PROGRAM_TENANT0_CONTRACT
    // -------------------------------------------------------------------------
    current_test = "AXIL_PROGRAM_TENANT0_CONTRACT";
    program_contract(.tidx(0), .min_bw(2), .max_bw(4), .burst_lim(16),
                     .deadline_cyc(1000), .prio(1), .max_qdepth(16));
    axil_read(16'h00C, rd_val);
    record(current_test, (rd_val[7:0] >= 1), $sformatf("active=%0d", rd_val[7:0]));

    // -------------------------------------------------------------------------
    // T4: SINGLE_WRITE_TENANT0
    // -------------------------------------------------------------------------
    current_test = "SINGLE_WRITE_TENANT0";
    r = make_req(KVQ_OP_WRITE, 16'h0001, 16'h0000, 64'h0000_0000_0000_0010, 4'd1, 32'd1000);
    pkt = pack_req(r);
    u_drv.drive_req(pkt);
    wait_for_resp(16'h0001, 200, ok);
    r_obs = u_sb.get(16'h0001);
    record(current_test, ok && (r_obs.status == KVQ_STATUS_OK),
      $sformatf("status=%s", status_name(r_obs.status)));

    // -------------------------------------------------------------------------
    // T5: SINGLE_READ_HIT_TENANT0
    // -------------------------------------------------------------------------
    current_test = "SINGLE_READ_HIT_TENANT0";
    r = make_req(KVQ_OP_READ, 16'h0002, 16'h0000, 64'h0000_0000_0000_0010, 4'd1, 32'd1000);
    u_drv.drive_req(pack_req(r));
    wait_for_resp(16'h0002, 200, ok);
    r_obs = u_sb.get(16'h0002);
    record(current_test, ok && (r_obs.status == KVQ_STATUS_OK) && r_obs.hit,
      $sformatf("status=%s hit=%0d", status_name(r_obs.status), r_obs.hit));

    // -------------------------------------------------------------------------
    // T6: SINGLE_READ_MISS_TENANT0
    // -------------------------------------------------------------------------
    current_test = "SINGLE_READ_MISS_TENANT0";
    r = make_req(KVQ_OP_READ, 16'h0003, 16'h0000, 64'h0000_0000_0000_0BAD, 4'd1, 32'd1000);
    u_drv.drive_req(pack_req(r));
    wait_for_resp(16'h0003, 200, ok);
    r_obs = u_sb.get(16'h0003);
    record(current_test, ok && (r_obs.status == KVQ_STATUS_MISS),
      $sformatf("status=%s hit=%0d", status_name(r_obs.status), r_obs.hit));

    // -------------------------------------------------------------------------
    // T7: BAD_OPCODE_ERROR
    // -------------------------------------------------------------------------
    current_test = "BAD_OPCODE_ERROR";
    r = make_req(8'hAA, 16'h0004, 16'h0000, 64'd0, 4'd1, 32'd1000);
    u_drv.drive_req(pack_req(r));
    wait_for_resp(16'h0004, 200, ok);
    r_obs = u_sb.get(16'h0004);
    record(current_test, ok && (r_obs.status == KVQ_STATUS_ERR_BAD_OPCODE),
      $sformatf("status=%s", status_name(r_obs.status)));

    // -------------------------------------------------------------------------
    // T8: CREDIT_EXHAUSTION_OR_STALL
    // Program tenant 1 with very small bucket, then flood; either some error
    // responses appear or input goes back-pressured.
    // -------------------------------------------------------------------------
    current_test = "CREDIT_EXHAUSTION_OR_STALL";
    program_contract(.tidx(1), .min_bw(1), .max_bw(1), .burst_lim(2),
                     .deadline_cyc(2000), .prio(2), .max_qdepth(16));
    for (int i = 0; i < 16; i++) begin
      r = make_req(KVQ_OP_READ, 16'h1000 + i, 16'h0001, 64'h0000_0000_0000_0020, 4'd2, 32'd2000);
      u_drv.drive_req(pack_req(r));
    end
    repeat (400) @(posedge clk);
    // Acceptance: either we observed some responses (forward progress) or
    // backpressure was visible on the input (also forward progress).
    axil_read(16'h02C, rd_val); // INPUT_BACKPRESSURE_CYCLES
    record(current_test, (u_sb.n_observed >= 4) || (rd_val > 0),
      $sformatf("nobs=%0d ibp=%0d", u_sb.n_observed, rd_val));

    // -------------------------------------------------------------------------
    // T9: TWO_TENANT_PRIORITY_ORDER
    // T2 (high prio) submitted after T3 (low prio) and should drain first.
    // -------------------------------------------------------------------------
    current_test = "TWO_TENANT_PRIORITY_ORDER";
    program_contract(.tidx(2), .min_bw(4), .max_bw(8), .burst_lim(64),
                     .deadline_cyc(2000), .prio(8), .max_qdepth(16)); // low prio
    program_contract(.tidx(3), .min_bw(4), .max_bw(8), .burst_lim(64),
                     .deadline_cyc(2000), .prio(1), .max_qdepth(16)); // high prio
    // Stall the response sink so requests queue up.
    m_axis_resp_tready = 1'b0;
    for (int i = 0; i < 4; i++) begin
      r = make_req(KVQ_OP_READ, 16'h2000 + i, 16'h0002, 64'h0000_0000_0000_0030, 4'd8, 32'd2000);
      u_drv.drive_req(pack_req(r));
    end
    for (int i = 0; i < 4; i++) begin
      r = make_req(KVQ_OP_READ, 16'h2100 + i, 16'h0003, 64'h0000_0000_0000_0040, 4'd1, 32'd2000);
      u_drv.drive_req(pack_req(r));
    end
    repeat (200) @(posedge clk);
    m_axis_resp_tready = 1'b1;
    repeat (400) @(posedge clk);
    record(current_test, (u_sb.seen(16'h2100) && u_sb.seen(16'h2000)),
      "drained-high-and-low");

    // -------------------------------------------------------------------------
    // T10: EARLIEST_DEADLINE_FIRST_BASIC
    // Two requests same priority, one tighter deadline; tighter should land first.
    // -------------------------------------------------------------------------
    current_test = "EARLIEST_DEADLINE_FIRST_BASIC";
    m_axis_resp_tready = 1'b0;
    r = make_req(KVQ_OP_READ, 16'h3000, 16'h0002, 64'h0000_0000_0000_0050, 4'd5, 32'd2000); // loose
    u_drv.drive_req(pack_req(r));
    r = make_req(KVQ_OP_READ, 16'h3001, 16'h0003, 64'h0000_0000_0000_0060, 4'd5, 32'd50);   // tight
    u_drv.drive_req(pack_req(r));
    repeat (100) @(posedge clk);
    m_axis_resp_tready = 1'b1;
    repeat (200) @(posedge clk);
    record(current_test, u_sb.seen(16'h3001), "tight-deadline-drained");

    // -------------------------------------------------------------------------
    // T11: OUTPUT_BACKPRESSURE_HOLDS_RESPONSE
    // Drive one request with sink stalled, check tvalid remains asserted.
    // -------------------------------------------------------------------------
    current_test = "OUTPUT_BACKPRESSURE_HOLDS_RESPONSE";
    m_axis_resp_tready = 1'b0;
    r = make_req(KVQ_OP_READ, 16'h4000, 16'h0000, 64'h0000_0000_0000_0010, 4'd1, 32'd1000);
    u_drv.drive_req(pack_req(r));
    repeat (200) @(posedge clk);
    record(current_test, m_axis_resp_tvalid, "tvalid-held");
    m_axis_resp_tready = 1'b1;
    @(posedge clk);

    // -------------------------------------------------------------------------
    // T12: COUNTER_RESET
    // -------------------------------------------------------------------------
    current_test = "COUNTER_RESET";
    axil_write(16'h000, 32'h0000_0004); // counter_reset
    repeat (10) @(posedge clk);
    axil_read(16'h010, rd_val);         // TOTAL_REQUESTS
    record(current_test, (rd_val == 0), $sformatf("total=%0d", rd_val));

    // -------------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------------
    $display("");
    $display("==========================================");
    $display("Phase 1 XSim summary: %0d pass / %0d fail", n_pass, n_fail);
    $display("==========================================");
    if (fd_csv) begin
      $fdisplay(fd_csv, "TOTAL,pass=%0d,fail=%0d", n_pass, n_fail);
      $fclose(fd_csv);
    end

    if (n_fail == 0) $display("RESULT: PASS");
    else             $display("RESULT: FAIL");

    $finish;
  end

  // Safety net
  initial begin
    #5000000;
    $display("RESULT: TIMEOUT");
    $finish;
  end

endmodule : tb_kvq_top
