// File: tb.sv
// Spec: sys-subsys-spec 2.3, 5, 6; testplan AB-01/03/05/06.
// Description: Self-checking transactions, response scoreboards and protocol assertions.
// Clock domain: clk_sys.
module tb;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;
    integer cycles = 0;
    integer checks = 0;
    always @(posedge clk) cycles <= cycles + 1;
    initial begin
        #2000000;
        $fatal(1, "FAIL timeout");
    end
    reg [3:0] axi_awid = 0;
    reg [31:0] axi_awaddr = 0;
    reg [7:0] axi_awlen = 0;
    reg [2:0] axi_awsize = 0;
    reg [1:0] axi_awburst = 0;
    reg axi_awvalid = 0;
    wire axi_awready;
    reg [63:0] axi_wdata = 0;
    reg [7:0] axi_wstrb = 0;
    reg axi_wlast = 0;
    reg axi_wvalid = 0;
    wire axi_wready;
    wire [3:0] axi_bid;
    wire [1:0] axi_bresp;
    wire axi_bvalid;
    reg axi_bready = 0;
    reg [3:0] axi_arid = 0;
    reg [31:0] axi_araddr = 0;
    reg [7:0] axi_arlen = 0;
    reg [2:0] axi_arsize = 0;
    reg [1:0] axi_arburst = 0;
    reg axi_arvalid = 0;
    wire axi_arready;
    wire [3:0] axi_rid;
    wire [63:0] axi_rdata;
    wire [1:0] axi_rresp;
    wire axi_rlast;
    wire axi_rvalid;
    reg axi_rready = 0;
    wire [15:0] paddr;
    wire psel;
    wire penable;
    wire pwrite;
    wire [31:0] pwdata;
    wire [3:0] pstrb;
    wire [31:0] prdata = 32'h55aa0000 | {16'b0, paddr};
    wire pready;
    reg pslverr = 0;
    integer delay_cycles = 0;
    integer waited = 0;
    integer transfers = 0;
    reg [15:0] expected_addr;
    reg expected_write;
    reg [31:0] expected_data;
    reg [3:0] expected_strb;
    assign pready = (waited >= delay_cycles);
    always @(posedge clk) begin
        if (!psel || !penable) waited <= 0;
        else if (!pready) waited <= waited + 1;
        if (rst_n && psel && penable && pready) begin
            transfers <= transfers + 1;
            if (paddr !== expected_addr || pwrite !== expected_write ||
                pstrb !== expected_strb || (pwrite && pwdata !== expected_data))
                $fatal(1, "FAIL APB payload addr=%h write=%b data=%h strb=%h t=%0t",
                    paddr, pwrite, pwdata, pstrb, $time);
        end
    end
    reg previous_setup = 0;
    reg previous_wait = 0;
    reg [52:0] saved_apb;
    always @(posedge clk) begin
        if (rst_n && psel && penable && !previous_setup && !previous_wait)
            $fatal(1, "FAIL ACCESS without SETUP");
        if (rst_n && previous_wait &&
            (!psel || !penable || {paddr,pwrite,pwdata,pstrb} !== saved_apb))
            $fatal(1, "FAIL stalled APB payload changed");
        previous_setup <= psel && !penable;
        previous_wait <= psel && penable && !pready;
        saved_apb <= {paddr,pwrite,pwdata,pstrb};
    end
    edrv32_bus_apb_bridge dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .axi_awid_i(axi_awid),
        .axi_awaddr_i(axi_awaddr),
        .axi_awlen_i(axi_awlen),
        .axi_awsize_i(axi_awsize),
        .axi_awburst_i(axi_awburst),
        .axi_awvalid_i(axi_awvalid),
        .axi_awready_o(axi_awready),
        .axi_wdata_i(axi_wdata),
        .axi_wstrb_i(axi_wstrb),
        .axi_wlast_i(axi_wlast),
        .axi_wvalid_i(axi_wvalid),
        .axi_wready_o(axi_wready),
        .axi_bid_o(axi_bid),
        .axi_bresp_o(axi_bresp),
        .axi_bvalid_o(axi_bvalid),
        .axi_bready_i(axi_bready),
        .axi_arid_i(axi_arid),
        .axi_araddr_i(axi_araddr),
        .axi_arlen_i(axi_arlen),
        .axi_arsize_i(axi_arsize),
        .axi_arburst_i(axi_arburst),
        .axi_arvalid_i(axi_arvalid),
        .axi_arready_o(axi_arready),
        .axi_rid_o(axi_rid),
        .axi_rdata_o(axi_rdata),
        .axi_rresp_o(axi_rresp),
        .axi_rlast_o(axi_rlast),
        .axi_rvalid_o(axi_rvalid),
        .axi_rready_i(axi_rready),
        .apb_paddr_o(paddr),
        .apb_psel_o(psel),
        .apb_penable_o(penable),
        .apb_pwrite_o(pwrite),
        .apb_pwdata_o(pwdata),
        .apb_pstrb_o(pstrb),
        .apb_prdata_i(prdata),
        .apb_pready_i(pready),
        .apb_pslverr_i(pslverr)
    );

    // Assert the AXI response contract, including cycles held under backpressure.
    reg held_r = 0;
    reg held_b = 0;
    reg [70:0] saved_r;
    reg [5:0] saved_b;
    always @(posedge clk) begin
        if (rst_n) begin
            if (held_r && {axi_rid, axi_rdata, axi_rresp, axi_rlast} !== saved_r)
                $fatal(1, "FAIL stalled R changed t=%0t", $time);
            if (held_r && !axi_rvalid) $fatal(1, "FAIL stalled RVALID dropped");
            if (held_b && {axi_bid, axi_bresp} !== saved_b)
                $fatal(1, "FAIL stalled B changed t=%0t", $time);
            if (held_b && !axi_bvalid) $fatal(1, "FAIL stalled BVALID dropped");
        end
        held_r <= rst_n && axi_rvalid && !axi_rready;
        held_b <= rst_n && axi_bvalid && !axi_bready;
        saved_r <= {axi_rid, axi_rdata, axi_rresp, axi_rlast};
        saved_b <= {axi_bid, axi_bresp};
    end

    task automatic read_check(input [31:0] addr, input [2:0] size,
        input integer len, input [1:0] resp, input integer legal);
        integer before_count;
        integer beat;
        reg [63:0] expected;
        begin
            before_count = transfers;
            expected_addr = addr[15:0];
            expected_write = 0;
            expected_strb = 0;
            expected = legal != 0 ? (addr[2] ?
                {32'h55aa0000 | {16'b0,addr[15:0]},32'b0} :
                {32'b0,32'h55aa0000 | {16'b0,addr[15:0]}}) : 64'b0;
            @(negedge clk);
            axi_araddr = addr; axi_arsize = size; axi_arlen = 8'(len);
            axi_arid = 9; axi_arburst = 1; axi_arvalid = 1;
            do @(posedge clk); while (!axi_arready);
            @(negedge clk); axi_arvalid = 0;
            repeat (3) @(negedge clk);
            axi_rready = 1;
            for (beat = 0; beat <= len; beat = beat + 1) begin
                do @(posedge clk); while (!axi_rvalid);
                if (axi_rid !== 9 || axi_rresp !== resp || axi_rdata !== expected ||
                    axi_rlast !== (beat == len))
                    $fatal(1, "FAIL AXI/APB read addr=%h beat=%0d exp=%h got=%h resp=%h",
                        addr,beat,expected,axi_rdata,axi_rresp);
                checks = checks + 1;
                @(negedge clk);
                if (beat < len) begin
                    axi_rready = 0;
                    repeat (2) @(negedge clk);
                    axi_rready = 1;
                end
            end
            axi_rready = 0;
            if (transfers - before_count != legal)
                $fatal(1, "FAIL APB read transfer count %0d exp=%0d",transfers-before_count,legal);
        end
    endtask
    task automatic write_check(input [31:0] addr, input [2:0] size,
        input integer len, input [7:0] strb, input [1:0] resp, input integer legal);
        integer before_count;
        integer beat;
        begin
            before_count = transfers;
            expected_addr = addr[15:0]; expected_write = 1;
            expected_data = addr[2] ? 32'hfedcba98 : 32'h76543210;
            expected_strb = addr[2] ? strb[7:4] : strb[3:0];
            @(negedge clk);
            axi_awaddr = addr; axi_awsize = size; axi_awlen = 8'(len);
            axi_awid = 6; axi_awburst = 1; axi_awvalid = 1;
            do @(posedge clk); while (!axi_awready);
            @(negedge clk); axi_awvalid = 0;
            for (beat = 0; beat <= len; beat = beat + 1) begin
                repeat (beat % 3) @(negedge clk);
                axi_wdata = 64'hfedcba9876543210; axi_wstrb = strb;
                axi_wlast = (beat == len); axi_wvalid = 1;
                do @(posedge clk); while (!axi_wready);
                if (beat < len && axi_bvalid) $fatal(1, "FAIL early B response");
                @(negedge clk); axi_wvalid = 0;
            end
            repeat (4) @(negedge clk);
            axi_bready = 1;
            do @(posedge clk); while (!axi_bvalid);
            if (axi_bid !== 6 || axi_bresp !== resp)
                $fatal(1, "FAIL AXI/APB write addr=%h exp=%h got=%h",addr,resp,axi_bresp);
            checks = checks + 1;
            @(negedge clk); axi_bready = 0;
            if (transfers - before_count != legal)
                $fatal(1, "FAIL APB write transfer count %0d exp=%0d",transfers-before_count,legal);
        end
    endtask
    integer slot;
    integer size;
    integer mask;
    initial begin
        repeat (3) @(negedge clk); rst_n = 1;
        // AB-01/06: all slots and both 32-bit halves, including every strobe nibble.
        for (slot = 0; slot < 16; slot = slot + 1) begin
            delay_cycles = slot % 4;
            read_check(32'h40000000 + (32'(slot) << 12),2,0,0,1);
            read_check(32'h40000004 + (32'(slot) << 12),2,0,0,1);
            for (mask = 0; mask < 16; mask = mask + 1) begin
                write_check(32'h40000000 + (32'(slot) << 12),2,0,8'(mask ^ 32'hb0),0,1);
                write_check(32'h40000004 + (32'(slot) << 12),2,0,8'((mask << 4) ^ 32'h0d),0,1);
            end
        end
        // AB-03: no APB at all for bad SIZE, alignment or burst length.
        for (size = 0; size < 8; size = size + 1) begin
            if (size != 2) begin
                read_check(32'h40000000,3'(size),0,2,0);
                write_check(32'h40000000,3'(size),0,8'hff,2,0);
            end
        end
        for (mask = 1; mask < 4; mask = mask + 1) begin
            read_check(32'h40000000 + 32'(mask),2,0,2,0);
            write_check(32'h40000000 + 32'(mask),2,0,8'hff,2,0);
        end
        read_check(32'h40000000,2,3,2,0);
        write_check(32'h40000000,2,3,8'hff,2,0);
        read_check(32'h40000004,2,255,2,0);
        write_check(32'h40000004,2,255,8'hff,2,0);
        // AB-05: APB errors are SLVERR on either AXI response channel.
        pslverr = 1;
        read_check(32'h40006004,2,0,2,1);
        write_check(32'h40006004,2,0,8'hf0,2,1);
        pslverr = 0;
        // Reset while APB is waiting cancels the transaction immediately.
        delay_cycles = 50;
        @(negedge clk); axi_arvalid = 1; axi_araddr = 32'h40000000;
        axi_arlen = 0; axi_arsize = 2;
        do @(posedge clk); while (!axi_arready);
        @(negedge clk); axi_arvalid = 0;
        wait (psel && penable);
        #1 rst_n = 0;
        #1;
        if (psel !== 0 || axi_rvalid !== 0 || axi_bvalid !== 0)
            $fatal(1,"FAIL bridge asynchronous reset");
        repeat (3) @(negedge clk); rst_n = 1; delay_cycles = 0;
        read_check(32'h40000000,2,0,0,1);
        $display("PASS AXI/APB checks=%0d transfers=%0d",checks,transfers);
        $finish;
    end
endmodule
