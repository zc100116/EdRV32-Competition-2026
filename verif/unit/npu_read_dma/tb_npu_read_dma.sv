// File: tb_npu_read_dma.sv
// Spec: npu-spec 3-6; edrv32-soc-spec 4.2, 7.1.
// Description: Self-checking isolated read_dma protocol and architectural tests.
// Clock: clk_npu.
`timescale 1ns/1ps
module tb_npu_read_dma;
    logic  clk_i = 0;
    logic  rst_n_i = 0;
    logic  stop_i = 0;
    logic  req_valid_i = 0;
    wire  req_ready_o;
    logic [31:0] req_addr_i = 0;
    logic [4:0] req_beats_i = 0;
    logic [31:0] req_tag_i = 0;
    wire  data_valid_o;
    logic  data_ready_i = 0;
    wire [255:0] data_o;
    wire [31:0] data_tag_o;
    wire [3:0] data_index_o;
    wire  data_last_o;
    wire  axi_arid_o;
    wire [31:0] axi_araddr_o;
    wire [3:0] axi_arlen_o;
    wire  axi_arvalid_o;
    logic  axi_arready_i = 0;
    logic  axi_rid_i = 0;
    logic [255:0] axi_rdata_i = 0;
    logic [1:0] axi_rresp_i = 0;
    logic  axi_rlast_i = 0;
    logic  axi_rvalid_i = 0;
    wire  axi_rready_o;
    wire  idle_o;
    wire  error_o;
    always #5 clk_i = !clk_i;
    edrv32_npu_read_dma u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .stop_i(stop_i),
        .req_valid_i(req_valid_i),
        .req_ready_o(req_ready_o),
        .req_addr_i(req_addr_i),
        .req_beats_i(req_beats_i),
        .req_tag_i(req_tag_i),
        .data_valid_o(data_valid_o),
        .data_ready_i(data_ready_i),
        .data_o(data_o),
        .data_tag_o(data_tag_o),
        .data_index_o(data_index_o),
        .data_last_o(data_last_o),
        .axi_arid_o(axi_arid_o),
        .axi_araddr_o(axi_araddr_o),
        .axi_arlen_o(axi_arlen_o),
        .axi_arvalid_o(axi_arvalid_o),
        .axi_arready_i(axi_arready_i),
        .axi_rid_i(axi_rid_i),
        .axi_rdata_i(axi_rdata_i),
        .axi_rresp_i(axi_rresp_i),
        .axi_rlast_i(axi_rlast_i),
        .axi_rvalid_i(axi_rvalid_i),
        .axi_rready_o(axi_rready_o),
        .idle_o(idle_o),
        .error_o(error_o)
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
        logic [31:0] tag;
        logic [3:0] index;
        logic last;
    } expected_t;
    expected_t expected[$];
    logic [31:0] return_tag = 0;
    logic [3:0] return_index = 0;
    int checked = 0;
    int errors = 0;
    int beats = 0;
    int addresses = 0;
    bit ar_stalled = 0;
    logic [35:0] held_ar;
    always @(posedge clk_i) begin
        expected_t value;
        if (rst_n_i) begin
            if (ar_stalled) check(axi_arvalid_o && {axi_araddr_o, axi_arlen_o} == held_ar,
                "AR must survive stall and stop");
            ar_stalled = axi_arvalid_o && !axi_arready_i;
            held_ar = {axi_araddr_o, axi_arlen_o};
            if (axi_arvalid_o && axi_arready_i) begin
                check(!axi_arid_o, "ordered read ID");
                addresses++;
            end
            if (data_valid_o && data_ready_i) begin
                check(expected.size() != 0, "no unsolicited DMA data");
                value = expected.pop_front();
                if ({data_o, data_tag_o, data_index_o, data_last_o}
                    != {value.data, value.tag, value.index, value.last})
                    $fatal(1, "FAIL expected tag/index=%08x/%0d actual=%08x/%0d time=%0t",
                        value.tag, value.index, data_tag_o, data_index_o, $time);
                checked++;
            end
            if (stop_i) expected.delete();
            if (axi_rvalid_i && axi_rready_o) begin
                beats++;
                if (!stop_i) begin
                    value = '{axi_rdata_i, return_tag, return_index, axi_rlast_i};
                    expected.push_back(value);
                end
            end
            if (error_o) errors++;
        end
    end
    task automatic request(input logic [31:0] addr, input logic [4:0] length,
        input logic [31:0] tag);
        req_addr_i = addr;
        req_beats_i = length;
        req_tag_i = tag;
        req_valid_i = 1;
        do @(posedge clk_i); while (!req_ready_o);
        @(negedge clk_i);
        #1;
        req_valid_i = 0;
    endtask
    task automatic response(input logic [31:0] tag, input int count, input bit bad);
        for (int n = 0; n < count; n++) begin
            axi_rvalid_i = 1;
            axi_rdata_i = {8{tag+32'(n)}};
            return_tag = tag;
            return_index = 4'(n);
            axi_rlast_i = n == count-1;
            axi_rresp_i = bad ? 2 : 0;
            do @(posedge clk_i); while (!axi_rready_o);
            @(negedge clk_i);
            #1;
        end
        axi_rvalid_i = 0;
    endtask
    initial begin
        tick;
        rst_n_i = 1;
        axi_arready_i = 1;
        data_ready_i = 1;
        request(32'h1000, 16, 32'ha0);
        request(32'h1200, 1, 32'hb0);
        request(32'h1fe0, 1, 32'hc0);
        request(32'h2000, 3, 32'hd0);
        tick;
        check(!req_ready_o, "four outstanding burst contexts");
        response(32'ha0, 16, 0);
        response(32'hb0, 1, 0);
        tick;
        data_ready_i = 0;
        response(32'hc0, 1, 1);
        repeat (7) tick;
        check(data_valid_o && data_tag_o == 32'hc0 && !idle_o, "return holding under backpressure");
        data_ready_i = 1;
        response(32'hd0, 3, 0);
        repeat (3) tick;
        check(idle_o && checked == 21 && beats == 21 && errors == 1, "normal drain and error");
        axi_arready_i = 0;
        request(32'h3000, 2, 32'he0);
        repeat (3) tick;
        stop_i = 1;
        repeat (5) tick;
        check(axi_arvalid_o && !req_ready_o && !idle_o, "pending AR retained on ABORT");
        axi_arready_i = 1;
        tick;
        response(32'he0, 2, 0);
        repeat (3) tick;
        check(idle_o && !data_valid_o && checked == 21,
            "ABORT discards internal data and drains R");
        stop_i = 0;
        request(32'h4000, 1, 32'hf0);
        tick;
        response(32'hf0, 1, 0);
        repeat (3) tick;
        check(idle_o && checked == 22 && addresses == 6, "restart after stop");
        $display("PASS read DMA tags, four outstanding, R stalls, errors and ABORT");
        $finish;
    end
endmodule
