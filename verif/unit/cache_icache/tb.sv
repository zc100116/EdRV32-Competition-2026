// File: cache_icache/tb.sv
// Spec: cache-spec; cache-testplan 2.2.
// Description: Self-checking directed cache unit tests.
// Clock domain: clk_sys (PMA is combinational).
module tb;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic ic_req_valid_i = 0;
    logic [31:0] ic_req_addr_i = 0;
    logic ic_req_ready_o;
    logic ic_resp_valid_o;
    logic [63:0] ic_resp_data_o;
    logic ic_resp_err_o;
    logic ic_kill_i = 0;
    logic ic_inv_i = 0;
    logic ic_inv_done_o;
    logic [3:0] axi_arid_o;
    logic [31:0] axi_araddr_o;
    logic [7:0] axi_arlen_o;
    logic [2:0] axi_arsize_o;
    logic [1:0] axi_arburst_o;
    logic axi_arvalid_o;
    logic axi_arready_i = 0;
    logic [3:0] axi_rid_i = 0;
    logic [63:0] axi_rdata_i = 0;
    logic [1:0] axi_rresp_i = 0;
    logic axi_rlast_i = 0;
    logic axi_rvalid_i = 0;
    logic axi_rready_o;
    always #5 clk_i = ~clk_i;
    edrv32_icache dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .ic_req_valid_i(ic_req_valid_i),
        .ic_req_addr_i(ic_req_addr_i),
        .ic_req_ready_o(ic_req_ready_o),
        .ic_resp_valid_o(ic_resp_valid_o),
        .ic_resp_data_o(ic_resp_data_o),
        .ic_resp_err_o(ic_resp_err_o),
        .ic_kill_i(ic_kill_i),
        .ic_inv_i(ic_inv_i),
        .ic_inv_done_o(ic_inv_done_o),
        .axi_arid_o(axi_arid_o),
        .axi_araddr_o(axi_araddr_o),
        .axi_arlen_o(axi_arlen_o),
        .axi_arsize_o(axi_arsize_o),
        .axi_arburst_o(axi_arburst_o),
        .axi_arvalid_o(axi_arvalid_o),
        .axi_arready_i(axi_arready_i),
        .axi_rid_i(axi_rid_i),
        .axi_rdata_i(axi_rdata_i),
        .axi_rresp_i(axi_rresp_i),
        .axi_rlast_i(axi_rlast_i),
        .axi_rvalid_i(axi_rvalid_i),
        .axi_rready_o(axi_rready_o)
    );
    task automatic tick;
        @(posedge clk_i); #1;
    endtask
    task automatic step;
        @(negedge clk_i); #1;
    endtask
    initial begin
        #200000;
        $fatal(1, "FAIL timeout");
    end
    logic [63:0] memory [0:8191];
    logic read_active = 0;
    logic [12:0] read_idx;
    logic [7:0] read_left;
    integer reads = 0;
    integer writes = 0;
    assign axi_arready_i = !read_active;
    assign axi_rvalid_i = read_active;
    assign axi_rdata_i = memory[read_idx];
    assign axi_rlast_i = read_left == 0;
    assign axi_rresp_i = 0;
    assign axi_rid_i = 0;
    always @(posedge clk_i) begin
        if (axi_arvalid_o && axi_arready_i) begin
            if (axi_arid_o != 0 || axi_arburst_o != 1) $fatal(1, "FAIL read attributes");
            read_active <= 1;
            read_idx <= axi_araddr_o[15:3];
            read_left <= axi_arlen_o;
            reads <= reads + 1;
        end else if (axi_rvalid_i && axi_rready_o) begin
            read_idx <= read_idx + 1;
            read_left <= read_left - 1;
            if (read_left == 0) read_active <= 0;
        end
    end
    task automatic fetch(input logic [31:0] addr, input logic [63:0] expected,
                         input integer expected_reads);
        step(); ic_req_valid_i = 1; ic_req_addr_i = addr;
        while (!ic_req_ready_o) tick();
        tick(); step(); ic_req_valid_i = 0;
        while (!ic_resp_valid_o) tick();
        if (ic_resp_err_o || ic_resp_data_o !== expected || reads != expected_reads)
            $fatal(1, "FAIL I %h data=%h reads=%0d", addr, ic_resp_data_o, reads);
        tick();
    endtask
    initial begin
        for (int i = 0; i < 8192; i++) memory[i] = {32'(i), 32'(i+4096)};
        tick(); step(); rst_n_i = 1;
        fetch(32'h10000000, memory[0], 1);
        if (dut.lru_r[0] != 1) $fatal(1, "FAIL I fill LRU way0");
        fetch(32'h10001000, memory[512], 2);
        if (dut.lru_r[0] != 0) $fatal(1, "FAIL I fill LRU way1");
        fetch(32'h10000008, memory[1], 2);
        if (dut.lru_r[0] != 1) $fatal(1, "FAIL I hit LRU way0");
        fetch(32'h10002000, memory[1024], 3);
        fetch(32'h10000000, memory[0], 3);
        fetch(32'h10001000, memory[512], 4);
        // Pipelined hits: one response for each accepted request, every cycle.
        step(); ic_req_valid_i = 1;
        for (int i = 0; i < 4; i++) begin
            ic_req_addr_i = 32'h10001000 + 32'(i*8);
            if (!ic_req_ready_o) $fatal(1, "FAIL I hit throughput ready");
            tick();
            if (!ic_resp_valid_o || ic_resp_data_o != memory[512+i])
                $fatal(1, "FAIL I hit throughput response");
            step();
        end
        ic_req_valid_i = 0;
        tick(); step(); ic_inv_i = 1; tick();
        if (!ic_inv_done_o) $fatal(1, "FAIL inv done");
        step(); ic_inv_i = 0;
        fetch(32'h10001000, memory[512], 5);
        fetch(32'h00000000, memory[0], 6);
        fetch(32'h00000000, memory[0], 7);
        // Invalidate overlaps an active refill: data returns, line remains invalid.
        step(); ic_req_valid_i = 1; ic_req_addr_i = 32'h10003000;
        tick(); step(); ic_req_valid_i = 0;
        while (!axi_rready_o) tick();
        step(); ic_inv_i = 1; tick();
        if (!ic_inv_done_o) $fatal(1, "FAIL in-flight invalidate done");
        step(); ic_inv_i = 0;
        while (!ic_resp_valid_o) tick();
        if (ic_resp_data_o != memory[1536]) $fatal(1, "FAIL invalidated fill data");
        tick();
        fetch(32'h10003000, memory[1536], 9);
        $display("PASS cache_icache"); $finish;
    end
endmodule
