// File: edrv32_cpu_early_tb.sv
// Spec: cpu-spec 3.3, 4.10; cpu-testplan A-02, A-03.
// Description: Exercise early model responses, fallback causes and read-only speculation.
// Clock: synthetic clk_sys, independent of the CPU implementation.
module edrv32_cpu_early_tb;
    import edrv32_cpu_memory::*;
    logic clk = 0;
    logic rst_n = 0;
    logic early_valid = 0;
    logic [31:0] early_addr = 0;
    wire early_hit;
    assign early_hit = |early_way_hit;
    wire [31:0] early_data;
    wire [1:0] early_way_hit;
    wire [63:0] early_way_data;
    assign early_data = ({32{early_way_hit[0]}} & early_way_data[31:0]) |
        ({32{early_way_hit[1]}} & early_way_data[63:32]);
    logic req_valid = 0;
    logic [31:0] req_addr = 0;
    logic req_store = 0;
    logic ready;
    logic resp_valid;
    wire [31:0] resp_data;
    wire [1:0] resp_way_hit;
    wire [63:0] resp_way_data;
    assign resp_data = ({32{resp_way_hit[0]}} & resp_way_data[31:0]) |
        ({32{resp_way_hit[1]}} & resp_way_data[63:32]);
    logic resp_err;
    logic unused_device;
    logic kill = 0;
    logic commit = 0;
    logic [31:0] store_data = 32'h55667788;
    logic unused_fence_done;
    logic unused_wb_event;
    logic unused_miss;
    logic unused_execute;
    logic buffer_valid;
    localparam BASE = 32'h10000100;
    edrv32_cpu_dc_model u_model (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .dc_early_valid_i(early_valid),
        .dc_early_addr_i(early_addr),
        .dc_early_way_hit_o(early_way_hit),
        .dc_early_way_data_o(early_way_data),
        .dc_req_valid_i(req_valid),
        .dc_req_addr_i(req_addr),
        .dc_req_store_i(req_store),
        .dc_req_size_i(2'd2),
        .dc_req_ready_o(ready),
        .dc_resp_valid_o(resp_valid),
        .dc_resp_way_data_o(resp_way_data),
        .dc_resp_way_hit_o(resp_way_hit),
        .dc_resp_err_o(resp_err),
        .dc_resp_device_o(unused_device),
        .dc_kill_i(kill),
        .dc_commit_i(commit),
        .dc_store_data_i(store_data),
        .dc_fence_i(1'b0),
        .dc_clean_all_i(1'b0),
        .dc_fence_done_o(unused_fence_done),
        .dc_wb_event_o(unused_wb_event),
        .miss_o(unused_miss),
        .device_execute_o(unused_execute),
        .write_buffer_valid_o(buffer_valid)
    );
    initial forever #5 clk = !clk;
    task automatic tick;
        @(negedge clk);
    endtask
    task automatic expect_query(input bit hit, input logic [2:0] reason);
        tick();
        if (early_hit != hit || (!hit && u_model.early_failure_r != reason))
            $fatal(1, "FAIL early query expected hit=%b reason=%0d actual=%b/%0d time=%0t",
                hit, reason, early_hit, u_model.early_failure_r, $time);
    endtask
    initial begin
        write_data(BASE, 2, 32'h11223344);
        write_data(BASE+4, 2, 32'haabbccdd);
        tick();
        rst_n = 1;
        early_valid = 1;
        early_addr = BASE;
        expect_query(1, 0);
        if (early_data != 32'h11223344 || u_model.active_r || buffer_valid ||
            device_accesses != 0 || read_data(BASE, 2) != 32'h11223344)
            $fatal(1, "FAIL speculative query changed observable state");
        // A successful query supplies M while the read port serves the next query.
        if (!ready) $fatal(1, "FAIL model unexpectedly not ready");
        req_valid = 1;
        req_addr = BASE;
        early_addr = BASE+4;
        expect_query(1, 0);
        if (!resp_valid || resp_err || resp_data != 32'h11223344)
            $fatal(1, "FAIL reused response expected=11223344 actual=%08x", resp_data);
        commit = 1;
        req_addr = BASE+4;
        early_valid = 0;
        tick();
        if (!resp_valid || resp_data != 32'haabbccdd)
            $fatal(1, "FAIL consecutive reuse expected=aabbccdd actual=%08x", resp_data);
        req_valid = 0;
        tick();
        commit = 0;
        early_valid = 1;
        early_addr = 32'h40000000;
        expect_query(0, 3);
        if (device_accesses != 0 || u_model.active_r)
            $fatal(1, "FAIL speculative device query executed a transaction");
        early_addr = BASE+8;
        u_model.early_miss_enabled = 1;
        u_model.early_miss_addr = BASE+8;
        expect_query(0, 2);
        if (u_model.active_r || u_model.delay_r != 0)
            $fatal(1, "FAIL speculative miss allocated a transaction");
        u_model.early_miss_enabled = 0;
        u_model.forced_ready_low = 1;
        expect_query(1, 0);
        u_model.forced_ready_low = 0;
        u_model.early_fail_pct = 100;
        // The random sample is registered; one clock establishes the setting.
        tick();
        expect_query(0, 1);
        u_model.early_fail_pct = 0;
        early_valid = 0;
        req_valid = 1;
        req_store = 1;
        req_addr = BASE;
        tick();
        req_valid = 0;
        early_valid = 1;
        early_addr = BASE;
        expect_query(0, 5);
        u_model.buffer_hold_cycles = 5;
        commit = 1;
        tick();
        commit = 0;
        expect_query(0, 4);
        if (read_data(BASE, 2) != 32'h11223344 || !buffer_valid)
            $fatal(1, "FAIL query drained or changed the held write buffer");
        early_valid = 0;
        repeat (7) tick();
        if (read_data(BASE, 2) != 32'h55667788)
            $fatal(1, "FAIL committed buffer did not drain");
        early_valid = 1;
        early_addr = BASE;
        expect_query(1, 0);
        kill = 1;
        early_valid = 0;
        tick();
        if (tohost_valid || tohost_value != 0 || u_model.active_r ||
            buffer_valid || device_accesses != 0 ||
            read_data(BASE, 2) != 32'h55667788)
            $fatal(1, "FAIL killed speculative query changed architectural state");
        $display("PASS early model: reuse, injected/miss/device/buffer/store failures, speculation");
        $finish;
    end
endmodule
