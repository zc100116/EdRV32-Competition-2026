// File: tb_npu_prof.sv
// Spec: T-NPU-PROF; npu-spec 2.4, 4, 5.4.
// Description: Read-only hierarchy observer around the unchanged NET-02 harness.
// Each busy edge owns exactly one category; arithmetic work is counted at A1.
// Clock: clk_npu.
`timescale 1ns/1ps
`define N u_tb.g_dut.u_dut
`define C u_tb.g_dut.u_dut.u_conv
`define D u_tb.g_dut.u_dut.u_conv.u_datapath
`define W u_tb.g_dut.u_dut.u_conv.u_datapath.u_window
module tb_npu_prof;
    tb_npu u_tb ();
    longint counts[68][14];
    longint work[68];
    longint starts[68];
    longint spans[68];
    longint clock_count;
    longint request_wait[3];
    longint request_max[3];
    bit [2:0] request_pending;
    bit [2:0] request_accept;
    bit seen[68];
    bit [6:0] descriptor;
    bit [3:0] category;
    int pixels;
    bit [3:0] reason;
    bit [3:0] reasons[6];
    initial begin
        for (int c = 0; c < 6; c++) reasons[c] = 6;
        for (int d = 0; d < 68; d++) begin
            work[d] = 0;
            for (int c = 0; c < 14; c++) counts[d][c] = 0;
        end
    end
    always @(posedge u_tb.clk_npu) begin
        clock_count++;
        request_pending = {`C.residual_candidate_w, `C.model_candidate_w, `C.line_candidate_w};
        request_accept = {`C.residual_accept_w, `C.model_accept_w, `C.line_accept_w};
        for (int r = 0; r < 3; r++) begin
            if (request_pending[r]) begin
                request_wait[r]++;
                if (request_wait[r] > request_max[r]) request_max[r] = request_wait[r];
                if (request_accept[r]) request_wait[r] = 0;
            end else request_wait[r] = 0;
        end
        reason = 6;
        // A1 issue reaches the PERF1 M1 valid six edges later.
        if (`N.state_r == 6 && `N.is_conv_r) begin
            if (`W.current_valid_r && `W.first_w && !`W.issue_w
                && `D.result_credit_o == 0) reason = 7;
            else if (`W.current_valid_r && `W.first_w && !`W.issue_w
                && `D.cfg_res_en_r && !`D.pair_residual_ready_w) reason = 8;
            else if (`W.current_valid_r && `W.first_w && !`W.issue_w) reason = 12;
            else if (!`W.current_valid_r && !`W.next_valid_r && `N.conv_model_wait_w)
                reason = seen[`N.cur_desc_r[6:0]] ? 3 : 2;
            else if (!`W.current_valid_r && !`W.next_valid_r && `N.conv_input_wait_w)
                reason = seen[`N.cur_desc_r[6:0]] ? 5 : 4;
        end
        if (`N.busy_w) begin
            descriptor = `N.cur_desc_r[6:0];
            if ((|`N.conv_start_w) || `N.nonconv_start_w)
                starts[descriptor] = clock_count;
            if (`N.local_done_w && `N.state_r == 6)
                spans[descriptor] = clock_count-starts[descriptor]+1;
            if (`W.issue_w && `N.is_conv_r && `N.state_r == 6) begin
                pixels = int'(`W.pixel0_valid_w)+int'(`W.pixel1_valid_w);
                work[descriptor] += 64'(pixels*(`W.current_in_c4_r ? 48 : 256));
                seen[descriptor] = 1;
            end
            if (`N.conv_mac_beat_w) begin
                category = 0;
            end else if (`N.state_r >= 1 && `N.state_r <= 4) category = 1;
            else if (`N.state_r == 7) category = 10;
            else if (`N.state_r == 6 && !`N.is_conv_r) category = 11;
            else if (`N.state_r == 6 && reasons[5] != 6) category = reasons[5];
            else if (`N.state_r == 6 && `C.all_submitted_r && `D.window_idle_w)
                category = (`D.mac_array_idle_w && `D.accum_idle_w
                    && `D.result_quant_idle_w && `D.residual_add_idle_w) ? 13 : 9;
            else category = 6;
            counts[descriptor][category]++;
            if (`N.state_r == 8) begin
                $display("REQUEST_WAIT line=%0d model=%0d residual=%0d",
                    request_max[0], request_max[1], request_max[2]);
                for (int d = 0; d < 68; d++) begin
                    $write("PROFILE d=%0d span=%0d work=%0d counts=", d, spans[d], work[d]);
                    for (int c = 0; c < 14; c++) $write("%0d,", counts[d][c]);
                    $write("\n");
                end
            end
        end
        for (int c = 5; c > 0; c--) reasons[c] = reasons[c-1];
        reasons[0] = reason;
    end
endmodule
