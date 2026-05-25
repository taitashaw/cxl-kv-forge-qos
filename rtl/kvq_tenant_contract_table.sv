// -----------------------------------------------------------------------------
// kvq_tenant_contract_table.sv
// Stores up to CONTRACT_TABLE_ENTRIES tenant contracts. Combinational lookup
// by tenant_id (truncated to TENANT_IDX_WIDTH). Unprogrammed entries fall back
// to default_contract() from kvq_pkg, guaranteeing the pipeline never blocks
// on unprogrammed tenants during Phase 1 bring-up.
//
// Programming interface is driven from kvq_axil_regs via a flat write port
// (one contract field per AXI write transaction). Field selection mirrors the
// AXI4-Lite register map laid out in docs/rtl_phase1_microarchitecture.md.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_tenant_contract_table
  import kvq_pkg::*;
(
  input  logic                            clk,
  input  logic                            rst_n,

  // Programming interface from AXI4-Lite shim
  input  logic                            cfg_write,
  input  logic [TENANT_IDX_WIDTH-1:0]     cfg_tenant_idx,
  input  logic [3:0]                      cfg_field_sel, // 0..14 (see docs)
  input  logic [31:0]                     cfg_wdata,

  input  logic                            cfg_reset_all,

  // Combinational lookup
  input  logic [TENANT_ID_WIDTH-1:0]      lookup_tenant_id,
  output kvq_contract_t                   lookup_contract,
  output logic                            lookup_valid,

  // Status
  output logic [7:0]                      active_tenant_count
);

  kvq_contract_t contracts [0:CONTRACT_TABLE_ENTRIES-1];
  logic          programmed [0:CONTRACT_TABLE_ENTRIES-1];

  logic [TENANT_IDX_WIDTH-1:0] lookup_idx;

  assign lookup_idx = lookup_tenant_id[TENANT_IDX_WIDTH-1:0];

  // Combinational lookup. contracts[] is initialized to the per-tenant default
  // on reset, so partially-programmed entries still return sensible values for
  // unwritten fields (otherwise mid-programming reads would observe zero
  // burst_credit_limit, draining buckets to zero).
  always_comb begin
    lookup_contract = contracts[lookup_idx];
    lookup_valid    = contracts[lookup_idx].valid;
  end

  // Active tenant count (programmed AND valid)
  always_comb begin
    active_tenant_count = '0;
    for (int j = 0; j < CONTRACT_TABLE_ENTRIES; j = j + 1) begin
      if (programmed[j] && contracts[j].valid) begin
        active_tenant_count = active_tenant_count + 8'd1;
      end
    end
  end

  // Programming. Reset initializes every entry to a per-tenant default contract
  // so unprogrammed reads return sane values.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int k = 0; k < CONTRACT_TABLE_ENTRIES; k = k + 1) begin
        contracts[k]  <= default_contract(16'(k));
        programmed[k] <= 1'b0;
      end
    end else if (cfg_reset_all) begin
      for (int k = 0; k < CONTRACT_TABLE_ENTRIES; k = k + 1) begin
        contracts[k]  <= default_contract(16'(k));
        programmed[k] <= 1'b0;
      end
    end else if (cfg_write) begin
      programmed[cfg_tenant_idx] <= 1'b1;
      unique case (cfg_field_sel)
        4'd0: contracts[cfg_tenant_idx].valid               <= cfg_wdata[0];
        4'd1: contracts[cfg_tenant_idx].min_bandwidth       <= cfg_wdata[15:0];
        4'd2: contracts[cfg_tenant_idx].max_bandwidth       <= cfg_wdata[15:0];
        4'd3: contracts[cfg_tenant_idx].burst_credit_limit  <= cfg_wdata[31:0];
        4'd4: contracts[cfg_tenant_idx].deadline_cycles     <= cfg_wdata[31:0];
        4'd5: contracts[cfg_tenant_idx].priority_class      <= cfg_wdata[3:0];
        4'd6: contracts[cfg_tenant_idx].max_queue_depth     <= cfg_wdata[15:0];
        4'd7: contracts[cfg_tenant_idx].eviction_protection <= cfg_wdata[0];
        4'd8: contracts[cfg_tenant_idx].security_domain     <= cfg_wdata[7:0];
        default: ;
      endcase
    end
  end

endmodule : kvq_tenant_contract_table
