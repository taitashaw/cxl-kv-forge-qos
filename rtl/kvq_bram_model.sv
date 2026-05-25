// -----------------------------------------------------------------------------
// kvq_bram_model.sv
// Phase 1 synthesizable single-port BRAM with a parallel valid-bit table for
// hit/miss decisions. Read latency is one cycle (registered output).
//
// MVP: no ECC, no tag-based associativity. The valid-bit table marks an entry
// as written/initialized. WRITE sets valid; READ checks valid.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "kvq_pkg.sv"

module kvq_bram_model
  import kvq_pkg::*;
#(
  parameter int ADDR_W  = BRAM_ADDR_WIDTH,
  parameter int DEPTH   = BRAM_DEPTH,
  parameter int DATA_W  = 64
) (
  input  logic                clk,
  input  logic                rst_n,

  input  logic                we,
  input  logic                re,
  input  logic [ADDR_W-1:0]   addr,
  input  logic [DATA_W-1:0]   wdata,
  input  logic                clear_valid_bits, // sync clear on soft_reset

  output logic [DATA_W-1:0]   rdata,
  output logic                rvalid,
  output logic                rhit
);

  (* ram_style = "block" *) logic [DATA_W-1:0] mem [0:DEPTH-1];
  // Valid-bit table as a flat vector for single-cycle bulk clear.
  logic [DEPTH-1:0]  valid_bit;

  logic [DATA_W-1:0] rdata_r;
  logic              rvalid_r;
  logic              rhit_r;

  // Data array: synchronous-only writes so Vivado can infer block RAM. The
  // memory contents are unreachable without a valid_bit, so we deliberately
  // skip data-array reset.
  always_ff @(posedge clk) begin
    if (we) begin
      mem[addr] <= wdata;
    end
    if (re) begin
      rdata_r <= mem[addr];
    end
  end

  // Valid-bit table and read-pipeline flags get async reset (small, regs).
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rvalid_r  <= 1'b0;
      rhit_r    <= 1'b0;
      valid_bit <= '0;
    end else begin
      if (clear_valid_bits) begin
        valid_bit <= '0;
      end else if (we) begin
        valid_bit[addr] <= 1'b1;
      end

      rvalid_r <= re;
      if (re) begin
        rhit_r <= valid_bit[addr];
      end
    end
  end

  assign rdata  = rdata_r;
  assign rvalid = rvalid_r;
  assign rhit   = rhit_r;

endmodule : kvq_bram_model
