// -----------------------------------------------------------------------------
// kvq_test_pkg.sv
// Testbench utility package: helper request builders, status string mapping,
// pass/fail bookkeeping. Simulation-only; never compiled into rtl/.
// -----------------------------------------------------------------------------

`ifndef KVQ_TEST_PKG_SV
`define KVQ_TEST_PKG_SV

`include "kvq_pkg.sv"

package kvq_test_pkg;

  import kvq_pkg::*;

  // Build a basic well-formed kvq_req_t given a few common fields.
  function automatic kvq_req_t make_req(
    input logic [7:0]  op,
    input logic [15:0] req_id,
    input logic [15:0] tid,
    input logic [63:0] addr,
    input logic [3:0]  prio,
    input logic [31:0] deadline
  );
    kvq_req_t r;
    r.opcode          = op;
    r.request_id      = req_id;
    r.tenant_id       = tid;
    r.session_id      = 16'd0;
    r.layer_id        = 8'd0;
    r.head_id         = 8'd0;
    r.token_id        = 32'd0;
    r.kv_address      = addr;
    r.payload_length  = 16'd0;
    r.prio            = prio;
    r.deadline_cycles = deadline;
    r.flags           = 8'd0;
    r.reserved        = 28'd0;
    return r;
  endfunction

  function automatic string status_name(input logic [7:0] s);
    case (s)
      KVQ_STATUS_OK:             return "OK";
      KVQ_STATUS_MISS:           return "MISS";
      KVQ_STATUS_ERR_BAD_OPCODE: return "ERR_BAD_OPCODE";
      KVQ_STATUS_ERR_QUEUE_FULL: return "ERR_QUEUE_FULL";
      KVQ_STATUS_ERR_NO_CREDIT:  return "ERR_NO_CREDIT";
      KVQ_STATUS_ERR_BAD_TENANT: return "ERR_BAD_TENANT";
      KVQ_STATUS_ERR_INTERNAL:   return "ERR_INTERNAL";
      default:                   return "UNKNOWN";
    endcase
  endfunction

  // AXI4-Lite contract programming address composer.
  // Layout (16-bit AWADDR):
  //   [15:12] = 4'h1   (contract window)
  //   [11:9]  = reserved
  //   [8:6]   = tenant index (0..7)
  //   [5:2]   = field select (see kvq_tenant_contract_table)
  //   [1:0]   = byte offset (ignored)
  function automatic logic [15:0] contract_addr(
    input int unsigned tidx,
    input int unsigned field
  );
    return 16'h1000 | ((tidx[2:0]) << 6) | ((field[3:0]) << 2);
  endfunction

endpackage : kvq_test_pkg

`endif // KVQ_TEST_PKG_SV
