// -----------------------------------------------------------------------------
// kvq_axil_regs.sv
// Simplified AXI4-Lite register file. Implements:
//   - Global control/config/status (0x000 .. 0x03C)
//   - Counter readback (mapped through 0x010 .. 0x03C)
//   - Tenant contract programming window (0x1000 + idx*0x40)
//
// MVP simplifications:
//   - Single in-flight write/read at a time
//   - WSTRB ignored; whole word writes assumed
//   - bresp/rresp always OKAY (2'b00)
//   - No exclusive access / region encoding
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_axil_regs
  import kvq_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // AXI4-Lite slave
  input  logic        s_axil_awvalid,
  output logic        s_axil_awready,
  input  logic [15:0] s_axil_awaddr,
  input  logic        s_axil_wvalid,
  output logic        s_axil_wready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0]  s_axil_wstrb,
  output logic        s_axil_bvalid,
  input  logic        s_axil_bready,
  output logic [1:0]  s_axil_bresp,

  input  logic        s_axil_arvalid,
  output logic        s_axil_arready,
  input  logic [15:0] s_axil_araddr,
  output logic        s_axil_rvalid,
  input  logic        s_axil_rready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0]  s_axil_rresp,

  // Control outputs
  output logic        ctl_enable,
  output logic        ctl_soft_reset,
  output logic        ctl_counter_reset,
  output logic        ctl_qos_enable,
  output logic [7:0]  ctl_memory_latency_cycles,

  // Status inputs
  input  logic        sts_error_seen,
  input  logic        sts_queue_full,
  input  logic        sts_deadline_miss_seen,
  input  logic [7:0]  sts_active_tenant_count,
  input  logic [15:0] sts_global_queue_occupancy,

  // Counter readback (from kvq_perf_counters)
  output logic [3:0]  cnt_sel,
  input  logic [31:0] cnt_data,

  // Contract programming bus (to kvq_tenant_contract_table)
  output logic                              cfg_write,
  output logic [TENANT_IDX_WIDTH-1:0]       cfg_tenant_idx,
  output logic [3:0]                        cfg_field_sel,
  output logic [31:0]                       cfg_wdata,
  output logic                              cfg_reset_all
);

  // Register storage
  logic [31:0] reg_control;     // bit0=enable, bit1=soft_reset, bit2=counter_reset, bit3=qos_enable
  logic [31:0] reg_config;      // bit[7:0] = memory_latency_cycles
  logic        soft_reset_pulse;
  logic        counter_reset_pulse;

  assign ctl_enable                = reg_control[0];
  assign ctl_qos_enable            = reg_control[3];
  assign ctl_memory_latency_cycles = reg_config[7:0];
  // soft_reset and counter_reset are single-cycle pulses driven from writes
  assign ctl_soft_reset    = soft_reset_pulse;
  assign ctl_counter_reset = counter_reset_pulse;

  // Write FSM
  typedef enum logic [1:0] { W_IDLE, W_DATA, W_RESP } wstate_e;
  wstate_e wstate;
  logic [15:0] aw_latched;

  // Read FSM
  typedef enum logic [1:0] { R_IDLE, R_RESP } rstate_e;
  rstate_e rstate;
  logic [15:0] ar_latched;

  // Defaults
  always_comb begin
    s_axil_awready = (wstate == W_IDLE);
    s_axil_wready  = (wstate == W_DATA);
    s_axil_bvalid  = (wstate == W_RESP);
    s_axil_bresp   = 2'b00;

    s_axil_arready = (rstate == R_IDLE);
    s_axil_rvalid  = (rstate == R_RESP);
    s_axil_rresp   = 2'b00;
  end

  // Read mux
  logic [31:0] rdata_r;
  always_comb begin
    cnt_sel = 4'd0;
    rdata_r = 32'h0;
    case (ar_latched)
      16'h000: rdata_r = reg_control;
      16'h004: rdata_r = {29'd0, sts_deadline_miss_seen, sts_queue_full, sts_error_seen};
      16'h008: rdata_r = reg_config;
      16'h00C: rdata_r = {24'd0, sts_active_tenant_count};
      16'h010: begin cnt_sel = 4'd0;  rdata_r = cnt_data; end // TOTAL_REQUESTS
      16'h014: begin cnt_sel = 4'd1;  rdata_r = cnt_data; end // READ_REQUESTS
      16'h018: begin cnt_sel = 4'd2;  rdata_r = cnt_data; end // WRITE_REQUESTS
      16'h01C: begin cnt_sel = 4'd3;  rdata_r = cnt_data; end // PREFETCH_REQUESTS
      16'h020: begin cnt_sel = 4'd4;  rdata_r = cnt_data; end // DEADLINE_MISS_COUNT
      16'h024: begin cnt_sel = 4'd5;  rdata_r = cnt_data; end // CREDIT_STARVATION_COUNT
      16'h028: begin cnt_sel = 4'd6;  rdata_r = cnt_data; end // MALFORMED_REQUEST_COUNT
      16'h02C: begin cnt_sel = 4'd7;  rdata_r = cnt_data; end // INPUT_BACKPRESSURE_CYCLES
      16'h030: begin cnt_sel = 4'd8;  rdata_r = cnt_data; end // OUTPUT_BACKPRESSURE_CYCLES
      16'h034: begin cnt_sel = 4'd9;  rdata_r = cnt_data; end // MAX_LATENCY
      16'h038: begin cnt_sel = 4'd10; rdata_r = cnt_data; end // CUMULATIVE_LATENCY
      16'h03C: begin cnt_sel = 4'd11; rdata_r = cnt_data; end // MAX_QUEUE_OCCUPANCY
      default: begin
        // Tenant contract readback window: 0x1000 + tenant_idx * 0x40 (write-only in MVP)
        rdata_r = 32'h0;
      end
    endcase
  end

  assign s_axil_rdata = rdata_r;

  // Write decode -> contract programming
  // Tenant idx = aw_latched[8:6], field_sel = aw_latched[5:2]
  logic        is_contract_write;
  logic [TENANT_IDX_WIDTH-1:0] ten_idx;
  logic [3:0]  field_sel;
  assign is_contract_write = (aw_latched[15:12] == 4'h1);
  assign ten_idx           = aw_latched[6 +: TENANT_IDX_WIDTH];
  assign field_sel         = aw_latched[5:2];

  // FSM update
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wstate              <= W_IDLE;
      rstate              <= R_IDLE;
      aw_latched          <= '0;
      ar_latched          <= '0;
      reg_control         <= 32'h0;
      reg_config          <= 32'h0000_0004; // default mem latency 4 cycles
      soft_reset_pulse    <= 1'b0;
      counter_reset_pulse <= 1'b0;
      cfg_write           <= 1'b0;
      cfg_tenant_idx      <= '0;
      cfg_field_sel       <= '0;
      cfg_wdata           <= '0;
      cfg_reset_all       <= 1'b0;
    end else begin
      // Default pulse clears
      soft_reset_pulse    <= 1'b0;
      counter_reset_pulse <= 1'b0;
      cfg_write           <= 1'b0;
      cfg_reset_all       <= 1'b0;

      // Auto-clear self-clearing control bits
      reg_control[1] <= 1'b0; // soft_reset
      reg_control[2] <= 1'b0; // counter_reset

      // Write FSM
      case (wstate)
        W_IDLE: if (s_axil_awvalid) begin
                  aw_latched <= s_axil_awaddr;
                  wstate     <= W_DATA;
                end
        W_DATA: if (s_axil_wvalid) begin
                  // Apply write
                  case (aw_latched)
                    16'h000: begin
                      reg_control <= s_axil_wdata;
                      if (s_axil_wdata[1]) soft_reset_pulse    <= 1'b1;
                      if (s_axil_wdata[2]) counter_reset_pulse <= 1'b1;
                    end
                    16'h008: reg_config <= s_axil_wdata;
                    default: begin
                      if (is_contract_write) begin
                        cfg_write       <= 1'b1;
                        cfg_tenant_idx  <= ten_idx;
                        cfg_field_sel   <= field_sel;
                        cfg_wdata       <= s_axil_wdata;
                      end
                    end
                  endcase
                  wstate <= W_RESP;
                end
        W_RESP: if (s_axil_bready) wstate <= W_IDLE;
        default: wstate <= W_IDLE;
      endcase

      // Read FSM
      case (rstate)
        R_IDLE: if (s_axil_arvalid) begin
                  ar_latched <= s_axil_araddr;
                  rstate     <= R_RESP;
                end
        R_RESP: if (s_axil_rready) rstate <= R_IDLE;
        default: rstate <= R_IDLE;
      endcase
    end
  end

endmodule : kvq_axil_regs
