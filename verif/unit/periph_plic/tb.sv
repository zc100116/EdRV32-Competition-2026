// File: tb.sv
// Spec: sys-subsys-testplan CL-01--CL-05 / PL-01--PL-05.
// Description: Self-checking AXI register and interrupt tests.
// Clock: clk_sys plus asynchronous source clock for PLIC.
module tb;
    localparam [31:0] BASE = 32'h30000000;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;
    reg [3:0] axi_awid_i;
    reg [31:0] axi_awaddr_i;
    reg [7:0] axi_awlen_i;
    reg [2:0] axi_awsize_i;
    reg [1:0] axi_awburst_i;
    reg axi_awvalid_i;
    wire axi_awready_o;
    reg [63:0] axi_wdata_i;
    reg [7:0] axi_wstrb_i;
    reg axi_wlast_i;
    reg axi_wvalid_i;
    wire axi_wready_o;
    wire [3:0] axi_bid_o;
    wire [1:0] axi_bresp_o;
    wire axi_bvalid_o;
    reg axi_bready_i;
    reg [3:0] axi_arid_i;
    reg [31:0] axi_araddr_i;
    reg [7:0] axi_arlen_i;
    reg [2:0] axi_arsize_i;
    reg [1:0] axi_arburst_i;
    reg axi_arvalid_i;
    wire axi_arready_o;
    wire [3:0] axi_rid_o;
    wire [63:0] axi_rdata_o;
    wire [1:0] axi_rresp_o;
    wire axi_rlast_o;
    wire axi_rvalid_o;
    reg axi_rready_i;
    reg [15:1] irq_src;
    wire meip;
    edrv32_periph_plic u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .axi_awid_i(axi_awid_i),
        .axi_awaddr_i(axi_awaddr_i),
        .axi_awlen_i(axi_awlen_i),
        .axi_awsize_i(axi_awsize_i),
        .axi_awburst_i(axi_awburst_i),
        .axi_awvalid_i(axi_awvalid_i),
        .axi_awready_o(axi_awready_o),
        .axi_wdata_i(axi_wdata_i),
        .axi_wstrb_i(axi_wstrb_i),
        .axi_wlast_i(axi_wlast_i),
        .axi_wvalid_i(axi_wvalid_i),
        .axi_wready_o(axi_wready_o),
        .axi_bid_o(axi_bid_o),
        .axi_bresp_o(axi_bresp_o),
        .axi_bvalid_o(axi_bvalid_o),
        .axi_bready_i(axi_bready_i),
        .axi_arid_i(axi_arid_i),
        .axi_araddr_i(axi_araddr_i),
        .axi_arlen_i(axi_arlen_i),
        .axi_arsize_i(axi_arsize_i),
        .axi_arburst_i(axi_arburst_i),
        .axi_arvalid_i(axi_arvalid_i),
        .axi_arready_o(axi_arready_o),
        .axi_rid_o(axi_rid_o),
        .axi_rdata_o(axi_rdata_o),
        .axi_rresp_o(axi_rresp_o),
        .axi_rlast_o(axi_rlast_o),
        .axi_rvalid_o(axi_rvalid_o),
        .axi_rready_i(axi_rready_i),
        .irq_src_i(irq_src),
        .irq_meip_o(meip)
    );
    task tick;
        @(posedge clk);
        #1;
    endtask
    task check(input bit condition, input string label_text);
        if (!condition) $fatal(1, "FAIL %s at %0t", label_text, $time);
    endtask
    task reset_device;
        @(negedge clk);
        rst_n = 0;
        repeat (3) tick();
        @(negedge clk);
        rst_n = 1;
        tick();
    endtask
    task wr_bus(input [31:0] offset, input [31:0] value,
            input [7:0] len = 0, input [2:0] size = 2);
        reg [1:0] response;
        response = (len != 0 || size != 2 || offset[1:0] != 0) ? 2 : 0;
        @(negedge clk);
        axi_awid_i = 4'hB;
        axi_awaddr_i = BASE + offset;
        axi_awlen_i = len;
        axi_awsize_i = size;
        axi_awvalid_i = 1;
        do tick(); while (!axi_wready_o);
        @(negedge clk);
        axi_awvalid_i = 0;
        // Exercise W arriving later than AW and a response held by BREADY.
        repeat (2) tick();
        for (integer beat = 0; beat <= int'(len); beat++) begin
            @(negedge clk);
            axi_wvalid_i = 1;
            axi_wdata_i = offset[2] ? {value, 32'hBAD0BAD0} : {32'hBAD0BAD0, value};
            axi_wstrb_i = offset[2] ? 8'hF0 : 8'h0F;
            axi_wlast_i = beat == int'(len);
            check(axi_wready_o, "write beat ready");
            tick();
            if (beat != int'(len)) check(!axi_bvalid_o, "no early write response");
        end
        @(negedge clk);
        axi_wvalid_i = 0;
        check(axi_bvalid_o && axi_bid_o == 4'hB && axi_bresp_o == response,
              "write response and ID");
        repeat (3) begin
            tick();
            check(axi_bvalid_o && axi_bid_o == 4'hB && axi_bresp_o == response,
                  "B stable during backpressure");
        end
        @(negedge clk);
        axi_bready_i = 1;
        tick();
        @(negedge clk);
        axi_bready_i = 0;
    endtask
    reg [63:0] read_snapshot;
    reg expect_claim_quiet = 0;
    task rd_bus(input [31:0] offset, output [31:0] value,
            input [7:0] len = 0, input [2:0] size = 2);
        reg [1:0] response;
        reg [63:0] held_data;
        response = (len != 0 || size != 2 || offset[1:0] != 0) ? 2 : 0;
        @(negedge clk);
        axi_arid_i = 4'hD;
        axi_araddr_i = BASE + offset;
        axi_arlen_i = len;
        axi_arsize_i = size;
        axi_arvalid_i = 1;
        check(axi_arready_o, "read address ready");
        @(posedge clk);
        read_snapshot = 0;
        #1;
        @(negedge clk);
        axi_arvalid_i = 0;
        held_data = axi_rdata_o;
        repeat (3) begin
            tick();
            check(axi_rvalid_o && axi_rid_o == 4'hD && axi_rdata_o === held_data &&
                  axi_rresp_o == response && axi_rlast_o == (len == 0),
                  "R stable during backpressure");
            if (expect_claim_quiet)
                check(!meip, "PL-02 claim clears at AR acceptance before R handshake");
        end
        value = offset[2] ? held_data[63:32] : held_data[31:0];
        for (integer beat = 0; beat <= int'(len); beat++) begin
            check(axi_rvalid_o && axi_rresp_o == response && axi_rid_o == 4'hD &&
                  axi_rlast_o == (beat == int'(len)), "read response, ID and RLAST");
            if (response != 0) check(axi_rdata_o == 0, "error read data zero");
            else if (offset[2]) check(axi_rdata_o[31:0] == 0, "high half placement");
            else check(axi_rdata_o[63:32] == 0, "low half placement");
            @(negedge clk);
            axi_rready_i = 1;
            tick();
        end
        check(!axi_rvalid_o, "read transaction ended");
        @(negedge clk);
        axi_rready_i = 0;
    endtask
    // One bus-driving process keeps every transaction on the same BFM path.
    reg command_valid = 0;
    reg command_done = 0;
    reg command_read;
    reg [31:0] command_offset;
    reg [31:0] command_data;
    reg [7:0] command_len;
    reg [2:0] command_size;
    reg [31:0] command_result;
    initial forever begin
        wait (command_valid);
        if (command_read)
            rd_bus(command_offset, command_result, command_len, command_size);
        else
            wr_bus(command_offset, command_data, command_len, command_size);
        command_done = 1;
        wait (!command_valid);
        command_done = 0;
    end
    task wr(input [31:0] offset, input [31:0] data,
            input [7:0] len = 0, input [2:0] size = 2);
        command_offset = offset;
        command_data = data;
        command_len = len;
        command_size = size;
        command_read = 0;
        command_valid = 1;
        wait (command_done);
        command_valid = 0;
        wait (!command_done);
    endtask
    task rd(input [31:0] offset, output [31:0] data,
            input [7:0] len = 0, input [2:0] size = 2);
        command_offset = offset;
        command_len = len;
        command_size = size;
        command_read = 1;
        command_valid = 1;
        wait (command_done);
        data = command_result;
        command_valid = 0;
        wait (!command_done);
    endtask
    integer mem_half = 3;
    reg mem_clk = 0;
    always begin
        #(mem_half); mem_clk = ~mem_clk;
    end
    initial begin
                axi_awid_i = 0;
        axi_awaddr_i = 0;
        axi_awlen_i = 0;
        axi_awsize_i = 0;
        axi_awburst_i = 0;
        axi_awvalid_i = 0;
        axi_wdata_i = 0;
        axi_wstrb_i = 0;
        axi_wlast_i = 0;
        axi_wvalid_i = 0;
        axi_bready_i = 0;
        axi_arid_i = 0;
        axi_araddr_i = 0;
        axi_arlen_i = 0;
        axi_arsize_i = 0;
        axi_arburst_i = 0;
        axi_arvalid_i = 0;
        axi_rready_i = 0;
        irq_src = 0;
        reset_device();
        check(!meip, "reset MEIP");
        rd('h1000, value); check(value == 0, "pending reset");
        wr('h2000, 'hFFFFFFFF);
        rd('h2000, value); check(value == 'hFFFE, "PL-05 enable bit zero");
        wr(4, 3); wr(8, 3); wr(20, 7);
        @(negedge clk); irq_src[1] = 1; irq_src[2] = 1; irq_src[5] = 1;
        repeat (8) tick(); check(meip, "PL-01 pending interrupts");
        rd('h200004, value); check(value == 5, "PL-01 highest priority");
        rd('h200004, value); check(value == 1, "PL-01 same priority low ID");
        expect_claim_quiet = 1;
        rd('h200004, value); check(value == 2, "PL-01 next tied source");
        expect_claim_quiet = 0;
        rd('h1000, value); check(value == 0 && !meip, "PL-02 claimed level held high");
        wr('h200004, 0); wr('h200004, 16); wr('h200004, 'h10005);
        rd('h1000, value); check(value == 0, "PL-02 incorrect completion ignored");
        wr('h200004, 5);
        rd('h1000, value); check(value == 'h20 && meip, "PL-03 level re-pends");
        wr('h200000, 7); check(!meip, "PL-01 equality with threshold");
        rd('h200004, value); check(value == 0, "PL-01 no eligible claim");
        wr('h200000, 6); check(meip, "PL-01 priority above threshold");
        wr('h2000, 0); check(!meip, "disabled pending masked");
        wr('h2000, 'hFFFE);
        // Invalid CLAIM reads cannot consume a pending interrupt.
        rd('h200004, value, 3);
        rd('h200004, value, 0, 3);
        rd('h200004, value); check(value == 5, "invalid claim had no effect");
        @(negedge clk); irq_src = 0;
        repeat (8) tick();
        wr('h200004, 1); wr('h200004, 2); wr('h200004, 5);
        wr('h200000, 0);
        // Priority zero never generates MEIP, but still appears in PENDING.
        @(negedge clk); irq_src[6] = 1;
        repeat (8) tick(); check(!meip, "PL-01 priority zero");
        rd('h1000, value); check(value == 'h40, "priority zero pending visible");
        wr(24, 1); rd('h200004, value); check(value == 6, "priority update");
        @(negedge clk); irq_src = 0;
        repeat (8) tick(); wr('h200004, 6);
        // PL-04: all eight memory-domain sources, with source faster and slower.
        for (integer ratio = 0; ratio < 2; ratio++) begin
            mem_half = ratio == 0 ? 3 : 11;
            for (integer n = 8; n <= 15; n++) begin
                wr(32'(4*n), 1);
                @(negedge mem_clk); irq_src[n] = 1;
                repeat (8) tick();
                rd('h200004, value); check(value == 32'(n), "PL-04 async source claim");
                @(negedge mem_clk); irq_src[n] = 0;
                repeat (8) tick(); wr('h200004, 32'(n));
            end
        end
        rd('h1000, value);
        check(value == 0 && (value & 'h99) == 0, "PL-05 reserved sources tied low");
        for (integer n = 1; n <= 15; n++) begin
            if (n != 3 && n != 4 && n != 7) begin
                wr(32'(4*n), 7);
                @(negedge clk); irq_src[n] = 1;
                repeat (8) tick();
                rd('h200004, value); check(value == 32'(n), "each connected source claimed");
                @(negedge clk); irq_src[n] = 0;
                repeat (8) tick(); wr('h200004, 32'(n));
            end
        end
        // Rejected writes leave the priority register unchanged.
        wr(4, 0, 3); wr(4, 0, 0, 1); wr(5, 0);
        rd(4, value); check(value == 7, "illegal write no effect");
        wr('h1010, 'hFFFFFFFF); rd('h1010, value); check(value == 0, "unlisted offset");
        $display("PASS PL-01 PL-02 PL-03 PL-04 PL-05");
        $finish;
    end
    reg [31:0] value;
    initial begin
        #200000;
        $fatal(1, "FAIL timeout");
    end
endmodule
