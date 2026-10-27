// File: tb_npu_write_dma.sv
// Spec: npu-spec 3-6; edrv32-soc-spec 4.2, 7.1.
// Description: Self-checking isolated write_dma protocol and architectural tests.
// Clock: clk_npu.
`timescale 1ns/1ps
module tb_npu_write_dma;
    logic  clk_i = 0;
    logic  rst_n_i = 0;
    logic  stop_i = 0;
    logic  req_valid_i = 0;
    wire  req_ready_o;
    logic [31:0] req_addr_i = 0;
    logic [4:0] req_beats_i = 0;
    logic  data_valid_i = 0;
    wire  data_ready_o;
    logic [255:0] data_i = 0;
    logic [31:0] data_strb_i = 0;
    wire  stream_idle_o;
    wire  axi_awid_o;
    wire [31:0] axi_awaddr_o;
    wire [3:0] axi_awlen_o;
    wire  axi_awvalid_o;
    logic  axi_awready_i = 0;
    wire [255:0] axi_wdata_o;
    wire [31:0] axi_wstrb_o;
    wire  axi_wlast_o;
    wire  axi_wvalid_o;
    logic  axi_wready_i = 0;
    logic  axi_bid_i = 0;
    logic [1:0] axi_bresp_i = 0;
    logic  axi_bvalid_i = 0;
    wire  axi_bready_o;
    wire  idle_o;
    wire  error_o;
    wire  beat_o;
    wire  response_wait_o;
    always #5 clk_i = !clk_i;
    edrv32_npu_write_dma u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .stop_i(stop_i),
        .req_valid_i(req_valid_i),
        .req_ready_o(req_ready_o),
        .req_addr_i(req_addr_i),
        .req_beats_i(req_beats_i),
        .data_valid_i(data_valid_i),
        .data_ready_o(data_ready_o),
        .data_i(data_i),
        .data_strb_i(data_strb_i),
        .stream_idle_o(stream_idle_o),
        .axi_awid_o(axi_awid_o),
        .axi_awaddr_o(axi_awaddr_o),
        .axi_awlen_o(axi_awlen_o),
        .axi_awvalid_o(axi_awvalid_o),
        .axi_awready_i(axi_awready_i),
        .axi_wdata_o(axi_wdata_o),
        .axi_wstrb_o(axi_wstrb_o),
        .axi_wlast_o(axi_wlast_o),
        .axi_wvalid_o(axi_wvalid_o),
        .axi_wready_i(axi_wready_i),
        .axi_bid_i(axi_bid_i),
        .axi_bresp_i(axi_bresp_i),
        .axi_bvalid_i(axi_bvalid_i),
        .axi_bready_o(axi_bready_o),
        .idle_o(idle_o),
        .error_o(error_o),
        .beat_o(beat_o),
        .response_wait_o(response_wait_o)
    );
    task automatic tick;
        @(posedge clk_i);
        @(negedge clk_i);
        #1;
    endtask
    task automatic check(input bit condition, input string label);
        if (!condition) $fatal(1, "FAIL %s time=%0t", label, $time);
    endtask
    initial begin
        #2000000;
        $fatal(1, "FAIL timeout");
    end
    typedef struct packed {
        logic [255:0] data;
        logic [31:0] strb;
        logic last;
    } expected_t;
    expected_t expected[$];
    bit source_last = 0;
    int checked = 0;
    int errors = 0;
    int addresses = 0;
    int bursts = 0;
    bit w_stalled = 0;
    bit aw_stalled = 0;
    logic [288:0] held_w;
    logic [35:0] held_aw;
    int cycle = 0;
    bit stall_w = 0;
    always @(negedge clk_i) begin
        cycle++;
        axi_wready_i = !stall_w || cycle % 5 == 0;
    end
    always @(posedge clk_i) begin
        expected_t value;
        if (rst_n_i) begin
            if (w_stalled) check(axi_wvalid_o
                && {axi_wdata_o, axi_wstrb_o, axi_wlast_o} == held_w, "W stable under stall");
            if (aw_stalled) check(axi_awvalid_o
                && {axi_awaddr_o, axi_awlen_o} == held_aw, "AW stable under stall and stop");
            w_stalled = axi_wvalid_o && !axi_wready_i;
            aw_stalled = axi_awvalid_o && !axi_awready_i;
            held_w = {axi_wdata_o, axi_wstrb_o, axi_wlast_o};
            held_aw = {axi_awaddr_o, axi_awlen_o};
            if (data_valid_i && data_ready_o) begin
                value = '{data_i, data_strb_i, source_last};
                expected.push_back(value);
            end
            if (axi_wvalid_o && axi_wready_i) begin
                check(expected.size() != 0, "no unsolicited W");
                value = expected.pop_front();
                check({axi_wdata_o, axi_wstrb_o, axi_wlast_o}
                    == {value.data, value.strb, value.last}, "W holding stage payload");
                checked++;
                if (axi_wlast_o) bursts++;
            end
            if (axi_awvalid_o && axi_awready_i) begin
                check(!axi_awid_o, "ordered write ID");
                addresses++;
            end
            if (error_o) errors++;
            check(axi_bready_o, "always drain B");
            check(beat_o == (axi_wvalid_o && axi_wready_i), "write PERF beat");
        end
    end
    task automatic request(input logic [31:0] addr, input logic [4:0] count);
        req_addr_i = addr;
        req_beats_i = count;
        req_valid_i = 1;
        do @(posedge clk_i); while (!req_ready_o);
        @(negedge clk_i);
        #1;
        req_valid_i = 0;
    endtask
    task automatic data(input int count, input int seed);
        for (int n = 0; n < count; n++) begin
            data_valid_i = 1;
            data_i = {8{32'(seed+n)}};
            data_strb_i = 32'h01010101 << (n % 8);
            source_last = (n == count-1);
            do @(posedge clk_i); while (!data_ready_o);
            @(negedge clk_i);
            #1;
        end
        data_valid_i = 0;
        while (!stream_idle_o) tick;
    endtask
    task automatic response(input bit bad);
        axi_bvalid_i = 1;
        axi_bresp_i = bad ? 3 : 0;
        tick;
        axi_bvalid_i = 0;
        axi_bresp_i = 0;
    endtask
    initial begin
        tick;
        rst_n_i = 1;
        axi_awready_i = 1;
        stall_w = 1;
        request(32'h1e00, 16);
        data(16, 100);
        check(!idle_o && response_wait_o && bursts == 1, "B-independent stream completion");
        request(32'h2000, 2);
        data(2, 200);
        check(bursts == 2 && addresses == 2, "next burst precedes previous B");
        response(0);
        response(1);
        tick;
        check(idle_o && checked == 18 && errors == 1, "B fence and specified error");
        stall_w = 0;
        for (int n = 0; n < 8; n++) begin
            request(32'h3000+32'(n*32), 1);
            data(1, n);
        end
        check(!req_ready_o && response_wait_o, "eight B credits");
        for (int n = 0; n < 8; n++) response(0);
        check(idle_o, "all B credits returned");
        axi_awready_i = 0;
        request(32'h4000, 3);
        repeat (4) tick;
        stop_i = 1;
        check(!req_ready_o, "no new requests after stop");
        axi_awready_i = 1;
        data(3, 900);
        check(!idle_o && stream_idle_o, "complete accepted burst on stop");
        response(0);
        check(idle_o && expected.size() == 0 && checked == 29, "ABORT drains W/B");
        stop_i = 0;
        request(32'h5000, 1);
        data(1, 1000);
        response(0);
        check(idle_o && checked == 30 && addresses == 12, "restart after stop");
        $display("PASS write DMA WSTRB, W stalls, eight B credits, errors and ABORT");
        $finish;
    end
endmodule
