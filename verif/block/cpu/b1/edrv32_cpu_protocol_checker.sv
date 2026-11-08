// File: edrv32_cpu_protocol_checker.sv
// Spec: cpu-spec 3.2, 3.3, 4.7; cpu-testplan 2.3
// Description: Check accepted transaction lifetimes and irreversible side effects.
// Clock: clk_sys. m_enter is supplied from the core's actual pipeline advance.
// Ordered model updates are immediate so later checks see this edge's transaction.
/* verilator lint_off BLKSEQ */
module edrv32_cpu_protocol_checker (
    input logic clk_i,
    input logic rst_n_i,
    input logic ic_req_valid_i,
    input logic [31:0] ic_req_addr_i,
    input logic ic_req_ready_i,
    input logic ic_resp_valid_i,
    input logic ic_resp_err_i,
    input logic ic_kill_i,
    input logic dc_req_valid_i,
    input logic dc_req_ready_i,
    input logic [31:0] dc_req_addr_i,
    input logic dc_req_store_i,
    input logic [1:0] dc_req_size_i,
    input logic dc_resp_valid_i,
    input logic dc_resp_err_i,
    input logic dc_resp_device_i,
    input logic dc_kill_i,
    input logic dc_commit_i,
    input logic m_enter_i,
    input logic redirect_flush_i,
    input logic device_execute_i
);
    bit dc_held_r;
    logic [34:0] dc_held_payload_r;
    bit dc_error_r;
    int ic_pending_r;
    bit dc_pending_r;
    bit dc_responded_r;
    bit dc_committed_r;

    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            dc_held_r = 0;
            dc_error_r = 0;
            ic_pending_r = 0;
            dc_pending_r = 0;
            dc_responded_r = 0;
            dc_committed_r = 0;
        end else begin
            if (ic_req_valid_i && ic_req_addr_i[2:0] != 0)
                $fatal(1, "FAIL cpu-spec 3.2: unaligned I$ address %08x at %0t",
                    ic_req_addr_i, $time);
            if (ic_resp_err_i && !ic_resp_valid_i)
                $fatal(1, "FAIL cpu-spec 3.2: I$ error without response at %0t", $time);
            if (ic_kill_i) begin
                ic_pending_r = 0;
            end else if (ic_resp_valid_i) begin
                if (ic_pending_r == 0)
                    $fatal(1, "FAIL cpu-spec 3.2: unsolicited I$ response at %0t", $time);
                ic_pending_r--;
            end
            if (ic_req_valid_i && ic_req_ready_i && !ic_kill_i)
                ic_pending_r++;
            if (dc_held_r && !dc_kill_i && !redirect_flush_i && (!dc_req_valid_i
                || {dc_req_addr_i, dc_req_store_i, dc_req_size_i} != dc_held_payload_r))
                $fatal(1, "FAIL cpu-spec 3.3: stalled D$ request changed at %0t", $time);
            dc_held_r = dc_req_valid_i && !dc_req_ready_i && !dc_kill_i && !redirect_flush_i;
            dc_held_payload_r = {dc_req_addr_i, dc_req_store_i, dc_req_size_i};
            if (dc_req_valid_i && dc_req_ready_i && !m_enter_i)
                $fatal(1, "FAIL cpu-spec 3.3: D$ request without entering M at %0t", $time);
            if (dc_resp_err_i && !dc_resp_valid_i)
                $fatal(1, "FAIL cpu-spec 3.3: D$ error without response at %0t", $time);
            if (dc_kill_i && dc_commit_i)
                $fatal(1, "FAIL cpu-spec 3.3: killed D$ request committed at %0t", $time);
            // A delayed execution pulse may coincide with a new request. Check old ownership first.
            if (device_execute_i && !(dc_pending_r && dc_committed_r))
                $fatal(1, "FAIL cpu-spec 4.7: device execution before commit at %0t", $time);
            if (dc_resp_valid_i && !dc_kill_i) begin
                if (!dc_pending_r || dc_responded_r)
                    $fatal(1, "FAIL cpu-spec 3.3: invalid D$ response lifetime at %0t",
                        $time);
                if (dc_resp_device_i && !dc_committed_r)
                    $fatal(1, "FAIL cpu-spec 4.7: device response before commit at %0t", $time);
                dc_responded_r = 1;
                dc_error_r = dc_resp_err_i;
            end
            if (dc_commit_i) begin
                if (!dc_pending_r || dc_committed_r)
                    $fatal(1, "FAIL cpu-spec 3.3: absent/repeated D$ commit at %0t", $time);
                if (!dc_resp_device_i && !dc_responded_r)
                    $fatal(1, "FAIL cpu-spec 3.3: cached commit before tag result at %0t", $time);
                if (dc_error_r)
                    $fatal(1, "FAIL cpu-spec 3.3: failed D$ access committed at %0t", $time);
                dc_committed_r = 1;
            end
            if (dc_kill_i || (dc_pending_r && dc_committed_r && dc_responded_r)) begin
                dc_pending_r = 0;
                dc_committed_r = 0;
                dc_responded_r = 0;
            end
            if (dc_req_valid_i && dc_req_ready_i) begin
                if (dc_pending_r)
                    $fatal(1, "FAIL cpu-spec 4.7: overlapping D$ requests at %0t", $time);
                dc_pending_r = 1;
                dc_error_r = 0;
            end
        end
    end
endmodule

/* verilator lint_on BLKSEQ */
