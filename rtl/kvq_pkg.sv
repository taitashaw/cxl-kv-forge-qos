// -----------------------------------------------------------------------------
// kvq_pkg.sv
// CXL-KV Forge-QoS - Phase 1 RTL package
//
// Declares request/response widths, opcodes, status codes, parameter struct,
// and pack/unpack helpers for the 256-bit AXI4-Stream request/response packets.
//
// This file is the single source of truth for bit-level packet layout. All
// RTL submodules and the XSim testbench import from here.
// -----------------------------------------------------------------------------

`ifndef KVQ_PKG_SV
`define KVQ_PKG_SV

`timescale 1ns/1ps

package kvq_pkg;

  // ---------------------------------------------------------------------------
  // Widths
  // ---------------------------------------------------------------------------
  parameter int REQUEST_WIDTH        = 256;
  parameter int RESPONSE_WIDTH       = 256;
  parameter int DATA_WIDTH           = 512;
  parameter int ADDR_WIDTH           = 64;
  parameter int TENANT_ID_WIDTH      = 16;
  parameter int SESSION_ID_WIDTH     = 16;
  parameter int LAYER_ID_WIDTH       = 8;
  parameter int HEAD_ID_WIDTH        = 8;
  parameter int TOKEN_ID_WIDTH       = 32;
  parameter int REQUEST_ID_WIDTH     = 16;
  parameter int PRIORITY_WIDTH       = 4;
  parameter int DEADLINE_WIDTH       = 32;
  parameter int CREDIT_WIDTH         = 32;

  // ---------------------------------------------------------------------------
  // Capacities (Phase 1 MVP)
  // ---------------------------------------------------------------------------
  parameter int MAX_TENANTS              = 8;
  parameter int TENANT_QUEUE_DEPTH       = 16;
  parameter int CONTRACT_TABLE_ENTRIES   = 8;
  parameter int BRAM_ADDR_WIDTH          = 12;
  parameter int BRAM_DEPTH               = 4096;

  // Derived
  parameter int TENANT_IDX_WIDTH = $clog2(MAX_TENANTS);
  parameter int QUEUE_OCC_WIDTH  = $clog2(TENANT_QUEUE_DEPTH + 1);

  // ---------------------------------------------------------------------------
  // Opcodes (8 bits)
  // ---------------------------------------------------------------------------
  typedef enum logic [7:0] {
    KVQ_OP_READ              = 8'h01,
    KVQ_OP_WRITE             = 8'h02,
    KVQ_OP_PREFETCH          = 8'h03,
    KVQ_OP_EVICT             = 8'h04,
    KVQ_OP_INVALIDATE        = 8'h05,
    KVQ_OP_QUERY_STATS       = 8'h06,
    KVQ_OP_RESET_STATS       = 8'h07,
    KVQ_OP_PROGRAM_CONTRACT  = 8'h08,
    KVQ_OP_RESET_CONTRACT    = 8'h09
  } kvq_opcode_e;

  // ---------------------------------------------------------------------------
  // Status codes (8 bits)
  // ---------------------------------------------------------------------------
  typedef enum logic [7:0] {
    KVQ_STATUS_OK              = 8'h00,
    KVQ_STATUS_MISS            = 8'h10,
    KVQ_STATUS_ERR_BAD_OPCODE  = 8'hE1,
    KVQ_STATUS_ERR_QUEUE_FULL  = 8'hE2,
    KVQ_STATUS_ERR_NO_CREDIT   = 8'hE3,
    KVQ_STATUS_ERR_BAD_TENANT  = 8'hE4,
    KVQ_STATUS_ERR_INTERNAL    = 8'hEF
  } kvq_status_e;

  // ---------------------------------------------------------------------------
  // Service-unit cost table (Phase 1 fixed costs)
  // ---------------------------------------------------------------------------
  function automatic logic [7:0] kvq_service_units(input logic [7:0] op);
    case (op)
      KVQ_OP_READ:        return 8'd1;
      KVQ_OP_WRITE:       return 8'd2;
      KVQ_OP_PREFETCH:    return 8'd1;
      KVQ_OP_EVICT:       return 8'd2;
      KVQ_OP_INVALIDATE:  return 8'd1;
      KVQ_OP_QUERY_STATS: return 8'd1;
      default:            return 8'd1;
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // Request packet struct
  //
  // Bit map (MSB first, total 256 bits):
  //   [255:248] opcode                       (8)
  //   [247:232] request_id                   (16)
  //   [231:216] tenant_id                    (16)
  //   [215:200] session_id                   (16)
  //   [199:192] layer_id                     (8)
  //   [191:184] head_id                      (8)
  //   [183:152] token_id                     (32)
  //   [151:88]  kv_address                   (64)
  //   [87:72]   payload_length               (16)
  //   [71:68]   priority                     (4)
  //   [67:36]   deadline_cycles              (32)
  //   [35:28]   flags                        (8)
  //   [27:0]    reserved_or_inline_payload   (28)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [7:0]   opcode;
    logic [15:0]  request_id;
    logic [15:0]  tenant_id;
    logic [15:0]  session_id;
    logic [7:0]   layer_id;
    logic [7:0]   head_id;
    logic [31:0]  token_id;
    logic [63:0]  kv_address;
    logic [15:0]  payload_length;
    logic [3:0]   prio;
    logic [31:0]  deadline_cycles;
    logic [7:0]   flags;
    logic [27:0]  reserved;
  } kvq_req_t;

  // ---------------------------------------------------------------------------
  // Response packet struct
  //
  // Bit map (MSB first, total 256 bits):
  //   [255:248] status                       (8)
  //   [247:232] request_id                   (16)
  //   [231:216] tenant_id                    (16)
  //   [215:184] latency_cycles               (32)
  //   [183]     deadline_miss                (1)
  //   [182]     hit                          (1)
  //   [181]     prefetch_used                (1)
  //   [180:173] error_code                   (8)
  //   [172:157] queue_occupancy_snapshot     (16)
  //   [156:125] credit_snapshot              (32)
  //   [124:0]   reserved_or_inline_payload   (125)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [7:0]   status;
    logic [15:0]  request_id;
    logic [15:0]  tenant_id;
    logic [31:0]  latency_cycles;
    logic         deadline_miss;
    logic         hit;
    logic         prefetch_used;
    logic [7:0]   error_code;
    logic [15:0]  queue_occupancy_snapshot;
    logic [31:0]  credit_snapshot;
    logic [124:0] reserved;
  } kvq_resp_t;

  // ---------------------------------------------------------------------------
  // Tenant contract entry
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic        valid;
    logic [15:0] min_bandwidth;       // credits per refill window (lower bound)
    logic [15:0] max_bandwidth;       // credits per refill window (cap)
    logic [31:0] burst_credit_limit;  // token-bucket depth
    logic [31:0] deadline_cycles;     // default per-tenant deadline budget
    logic [3:0]  priority_class;      // lower wins
    logic [15:0] max_queue_depth;     // per-tenant queue cap
    logic        eviction_protection; // reserved for future use
    logic [7:0]  security_domain;     // reserved for future use
  } kvq_contract_t;

  // ---------------------------------------------------------------------------
  // unpack_req: bit-vector -> kvq_req_t
  // ---------------------------------------------------------------------------
  function automatic kvq_req_t unpack_req(input logic [REQUEST_WIDTH-1:0] data);
    kvq_req_t r;
    r.opcode          = data[255:248];
    r.request_id      = data[247:232];
    r.tenant_id       = data[231:216];
    r.session_id      = data[215:200];
    r.layer_id        = data[199:192];
    r.head_id         = data[191:184];
    r.token_id        = data[183:152];
    r.kv_address      = data[151:88];
    r.payload_length  = data[87:72];
    r.prio            = data[71:68];
    r.deadline_cycles = data[67:36];
    r.flags           = data[35:28];
    r.reserved        = data[27:0];
    return r;
  endfunction

  // ---------------------------------------------------------------------------
  // pack_req: kvq_req_t -> bit-vector (used by testbench / trace driver)
  // ---------------------------------------------------------------------------
  function automatic logic [REQUEST_WIDTH-1:0] pack_req(input kvq_req_t r);
    logic [REQUEST_WIDTH-1:0] d;
    d[255:248] = r.opcode;
    d[247:232] = r.request_id;
    d[231:216] = r.tenant_id;
    d[215:200] = r.session_id;
    d[199:192] = r.layer_id;
    d[191:184] = r.head_id;
    d[183:152] = r.token_id;
    d[151:88]  = r.kv_address;
    d[87:72]   = r.payload_length;
    d[71:68]   = r.prio;
    d[67:36]   = r.deadline_cycles;
    d[35:28]   = r.flags;
    d[27:0]    = r.reserved;
    return d;
  endfunction

  // ---------------------------------------------------------------------------
  // pack_resp: kvq_resp_t -> bit-vector for AXIS m_axis_resp_tdata
  // ---------------------------------------------------------------------------
  function automatic logic [RESPONSE_WIDTH-1:0] pack_resp(input kvq_resp_t resp);
    logic [RESPONSE_WIDTH-1:0] d;
    d[255:248] = resp.status;
    d[247:232] = resp.request_id;
    d[231:216] = resp.tenant_id;
    d[215:184] = resp.latency_cycles;
    d[183]     = resp.deadline_miss;
    d[182]     = resp.hit;
    d[181]     = resp.prefetch_used;
    d[180:173] = resp.error_code;
    d[172:157] = resp.queue_occupancy_snapshot;
    d[156:125] = resp.credit_snapshot;
    d[124:0]   = resp.reserved;
    return d;
  endfunction

  // ---------------------------------------------------------------------------
  // unpack_resp: bit-vector -> kvq_resp_t (testbench/scoreboard use)
  // ---------------------------------------------------------------------------
  function automatic kvq_resp_t unpack_resp(input logic [RESPONSE_WIDTH-1:0] data);
    kvq_resp_t r;
    r.status                   = data[255:248];
    r.request_id               = data[247:232];
    r.tenant_id                = data[231:216];
    r.latency_cycles           = data[215:184];
    r.deadline_miss            = data[183];
    r.hit                      = data[182];
    r.prefetch_used            = data[181];
    r.error_code               = data[180:173];
    r.queue_occupancy_snapshot = data[172:157];
    r.credit_snapshot          = data[156:125];
    r.reserved                 = data[124:0];
    return r;
  endfunction

  // ---------------------------------------------------------------------------
  // is_known_opcode: opcode validation
  //
  // The valid opcodes are the consecutive range 0x01..0x09 (READ through
  // RESET_CONTRACT). Expressed as a simple arithmetic compare so Vivado
  // opt_design does not have to decompose a sparse case statement into a
  // LUT4 cone (which triggered "missing input I0" trims in Vivado 2025.2).
  // ---------------------------------------------------------------------------
  function automatic logic is_known_opcode(input logic [7:0] op);
    return (op >= 8'h01) && (op <= 8'h09);
  endfunction

  // ---------------------------------------------------------------------------
  // Default tenant contract (used by kvq_tenant_contract_table on unprogrammed
  // entries). MVP behavior: every tenant_id is given a permissive contract so
  // the pipeline never blocks on missing programming during early bring-up.
  // ---------------------------------------------------------------------------
  function automatic kvq_contract_t default_contract(input logic [15:0] tenant_id);
    kvq_contract_t c;
    c.valid               = 1'b1;
    c.min_bandwidth       = 16'd1;
    c.max_bandwidth       = 16'd4;
    c.burst_credit_limit  = 32'd16;
    c.deadline_cycles     = 32'd1000;
    c.priority_class      = tenant_id[3:0];
    c.max_queue_depth     = 16'(TENANT_QUEUE_DEPTH);
    c.eviction_protection = 1'b0;
    c.security_domain     = 8'd0;
    return c;
  endfunction

endpackage : kvq_pkg

`endif // KVQ_PKG_SV
