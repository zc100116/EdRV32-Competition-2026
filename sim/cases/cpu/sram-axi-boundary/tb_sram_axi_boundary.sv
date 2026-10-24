`timescale 1ns/1ps
`include "edrv32_axi4.vh"

module tb_sram_axi_boundary;
    localparam [31:0] BASE_ADDR = 32'h1000_0000;
    localparam integer NUM_WORDS = 2048; // 8 KiB, so a 4 KiB crossing can remain in range.
    localparam [31:0] END_ADDR = BASE_ADDR + NUM_WORDS * 4;

    reg clk;
    reg rst_n;
    integer checks;
    integer page_beat;
    integer burst_len;
    integer random_case;

    reg [`AXI_ID_W-1:0] awid;
    reg [31:0] awaddr;
    reg [`AXI_LEN_W-1:0] awlen;
    reg [`AXI_SIZE_W-1:0] awsize;
    reg [`AXI_BURST_W-1:0] awburst;
    reg awvalid;
    wire awready;
    reg [`AXI_DATA_W-1:0] wdata;
    reg [`AXI_STRB_W-1:0] wstrb;
    reg wlast;
    reg wvalid;
    wire wready;
    wire [`AXI_ID_W-1:0] bid;
    wire [`AXI_RESP_W-1:0] bresp;
    wire bvalid;
    reg bready;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic reference_write_error;
        input [31:0] address;
        input [`AXI_LEN_W-1:0] length;
        input [`AXI_SIZE_W-1:0] size;
        input [`AXI_BURST_W-1:0] burst;
        reg [14:0] burst_length;
        reg [31:0] last_address;
        reg [14:0] end_offset;
        reg size_ok;
        begin
            burst_length = size[0] ? ({7'b0, length} << 3)
                                    : ({7'b0, length} << 2);
            last_address = address + {17'b0, burst_length};
            end_offset = {3'b000, address[11:0]} + burst_length +
                         (size[0] ? 15'd8 : 15'd4);
            size_ok = (size == `AXI_SIZE_8B) ||
                      ((size == `AXI_SIZE_4B) && (length == 0));
            reference_write_error = (address < BASE_ADDR) ||
                                    (last_address >= END_ADDR) ||
                                    (last_address < address) ||
                                    (address[1:0] != 2'b00) ||
                                    (address[2] && (size == `AXI_SIZE_8B)) ||
                                    !size_ok ||
                                    (burst != `AXI_BURST_INCR) ||
                                    (end_offset > 15'd4096);
        end
    endfunction

    // Candidate used to test the algebra before the production RTL changes.
    // A valid 8-byte beat is naturally aligned, so bit 9 of
    // {0,address[11:3]} + LEN says whether the last beat starts in a new page.
    // A valid 4-byte request is one beat and therefore cannot cross 4 KiB.
    function automatic candidate_write_error;
        input [31:0] address;
        input [`AXI_LEN_W-1:0] length;
        input [`AXI_SIZE_W-1:0] size;
        input [`AXI_BURST_W-1:0] burst;
        reg [14:0] burst_length;
        reg [31:0] last_address;
        reg [9:0] last_page_beat;
        reg size_ok;
        begin
            burst_length = size[0] ? ({7'b0, length} << 3)
                                    : ({7'b0, length} << 2);
            last_address = address + {17'b0, burst_length};
            last_page_beat = {1'b0, address[11:3]} + {2'b00, length};
            size_ok = (size == `AXI_SIZE_8B) ||
                      ((size == `AXI_SIZE_4B) && (length == 0));
            candidate_write_error = (address < BASE_ADDR) ||
                                    (last_address >= END_ADDR) ||
                                    (last_address < address) ||
                                    (address[1:0] != 2'b00) ||
                                    (address[2] && (size == `AXI_SIZE_8B)) ||
                                    !size_ok ||
                                    (burst != `AXI_BURST_INCR) ||
                                    ((size == `AXI_SIZE_8B) && last_page_beat[9]);
        end
    endfunction

    task automatic check_true;
        input condition;
        input [8*112-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic check_formula;
        input [31:0] address;
        input [`AXI_LEN_W-1:0] length;
        input [`AXI_SIZE_W-1:0] size;
        input [`AXI_BURST_W-1:0] burst;
        reg expected;
        begin
            awaddr = address;
            awlen = length;
            awsize = size;
            awburst = burst;
            #1;
            expected = reference_write_error(address, length, size, burst);
            check_true(candidate_write_error(address, length, size, burst) ===
                       expected,
                       "candidate boundary predicate differs from reference");
            check_true(dut.write_req_err_w === expected,
                       "sram_axi boundary predicate differs from reference");
        end
    endtask

    task automatic issue_write;
        input [31:0] address;
        input [`AXI_LEN_W-1:0] length;
        input [`AXI_SIZE_W-1:0] size;
        input [`AXI_BURST_W-1:0] burst;
        input expected_error;
        integer beat;
        begin
            @(negedge clk);
            awid = 4'ha;
            awaddr = address;
            awlen = length;
            awsize = size;
            awburst = burst;
            awvalid = 1'b1;
            @(posedge clk);
            while (!awready) @(posedge clk);
            #1;
            awvalid = 1'b0;
            check_true(wready, "WREADY did not assert in the cycle after AW");

            for (beat = 0; beat <= length; beat = beat + 1) begin
                @(negedge clk);
                wdata = {32'hcafe_0000 + beat, 32'h1234_0000 + beat};
                wstrb = 8'hff;
                wlast = (beat == length);
                wvalid = 1'b1;
                @(posedge clk);
                while (!wready) @(posedge clk);
                #1;
                wvalid = 1'b0;
                wlast = 1'b0;
            end

            check_true(bvalid, "BVALID missing after final W beat");
            check_true(bid == 4'ha, "BID was not retained from AW");
            check_true(bresp == (expected_error ? `AXI_RESP_SLVERR
                                                : `AXI_RESP_OKAY),
                       "BRESP did not match boundary classification");
            @(negedge clk);
            bready = 1'b1;
            @(posedge clk);
            #1;
            bready = 1'b0;
            check_true(!bvalid, "BVALID did not clear after handshake");
        end
    endtask

    sram_axi #(
        .NUM_WORDS (NUM_WORDS),
        .BASE_ADDR (BASE_ADDR),
        .ID_W      (`AXI_ID_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .awid_i(awid), .awaddr_i(awaddr), .awlen_i(awlen),
        .awsize_i(awsize), .awburst_i(awburst),
        .awvalid_i(awvalid), .awready_o(awready),
        .wdata_i(wdata), .wstrb_i(wstrb), .wlast_i(wlast),
        .wvalid_i(wvalid), .wready_o(wready),
        .bid_o(bid), .bresp_o(bresp), .bvalid_o(bvalid), .bready_i(bready),
        .arid_i({`AXI_ID_W{1'b0}}), .araddr_i(32'd0),
        .arlen_i({`AXI_LEN_W{1'b0}}), .arsize_i(`AXI_SIZE_4B),
        .arburst_i(`AXI_BURST_INCR), .arvalid_i(1'b0), .arready_o(),
        .rid_o(), .rdata_o(), .rresp_o(), .rlast_o(), .rvalid_o(),
        .rready_i(1'b0)
    );

    initial begin
        checks = 0;
        rst_n = 1'b0;
        awid = 0;
        awaddr = BASE_ADDR;
        awlen = 0;
        awsize = `AXI_SIZE_4B;
        awburst = `AXI_BURST_INCR;
        awvalid = 1'b0;
        wdata = 0;
        wstrb = 0;
        wlast = 1'b0;
        wvalid = 1'b0;
        bready = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Exhaust every aligned 8-byte start in one page and every AXI LEN.
        for (page_beat = 0; page_beat < 512; page_beat = page_beat + 1)
            for (burst_len = 0; burst_len < 256; burst_len = burst_len + 1)
                check_formula(BASE_ADDR + page_beat * 8,
                              burst_len[`AXI_LEN_W-1:0],
                              `AXI_SIZE_8B, `AXI_BURST_INCR);

        // Include arbitrary invalid encodings, address overflow and misalignment.
        for (random_case = 0; random_case < 10000;
             random_case = random_case + 1)
            check_formula($urandom, $urandom, $urandom, $urandom);
        check_formula(32'hffff_fff8, 8'd1, `AXI_SIZE_8B,
                      `AXI_BURST_INCR);
        check_formula(BASE_ADDR - 4, 8'd0, `AXI_SIZE_4B,
                      `AXI_BURST_INCR);
        check_formula(END_ADDR - 8, 8'd1, `AXI_SIZE_8B,
                      `AXI_BURST_INCR);

        // Real handshakes preserve the current no-extra-validation-cycle contract.
        issue_write(BASE_ADDR, 8'd0, `AXI_SIZE_4B,
                    `AXI_BURST_INCR, 1'b0);
        issue_write(BASE_ADDR + 32'd16, 8'd1, `AXI_SIZE_8B,
                    `AXI_BURST_INCR, 1'b0);
        issue_write(BASE_ADDR + 32'h0000_0ff8, 8'd1, `AXI_SIZE_8B,
                    `AXI_BURST_INCR, 1'b1);
        issue_write(END_ADDR - 8, 8'd1, `AXI_SIZE_8B,
                    `AXI_BURST_INCR, 1'b1);
        issue_write(BASE_ADDR + 4, 8'd0, `AXI_SIZE_8B,
                    `AXI_BURST_INCR, 1'b1);
        issue_write(BASE_ADDR, 8'd1, `AXI_SIZE_4B,
                    `AXI_BURST_INCR, 1'b1);
        issue_write(BASE_ADDR, 8'd0, `AXI_SIZE_4B,
                    `AXI_BURST_FIXED, 1'b1);

        $display("PASS: SRAM AXI boundary equivalence and write protocol (%0d checks)", checks);
        $finish;
    end
endmodule
