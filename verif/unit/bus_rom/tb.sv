// File: tb.sv
// Spec: sys-subsys-spec 2.2, 5, 6, 7; testplan MEM-01/02.
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
    edrv32_bus_rom dut (
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
        .axi_rready_i(axi_rready)
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
    reg [63:0] reference [0:2047];
    localparam [31:0] BASE = 32'h00000000;
    task automatic read_check(input [31:0] addr, input [2:0] size,
        input integer len, input integer stall);
        integer beat;
        integer accepted;
        integer previous;
        integer idx;
        begin
            @(negedge clk);
            axi_araddr = addr;
            axi_arsize = size;
            axi_arlen = 8'(len);
            axi_arid = 4'ha;
            axi_arburst = 1;
            axi_arvalid = 1;
            do @(posedge clk); while (!axi_arready);
            accepted = cycles;
            @(negedge clk);
            axi_arvalid = 0;
            axi_rready = 0;
            repeat (stall) @(negedge clk);
            axi_rready = 1;
            previous = 0;
            for (beat = 0; beat <= len; beat = beat + 1) begin
                do @(posedge clk); while (!axi_rvalid);
                idx = int'(((addr - BASE) + (beat << size)) >> 3);
                if (axi_rid !== 4'ha || axi_rresp !== 0 || axi_rlast !== (beat == len) ||
                    axi_rdata !== reference[idx])
                    $fatal(1, "FAIL read addr=%h beat=%0d exp=%h got=%h resp=%h last=%b t=%0t",
                        addr, beat, reference[idx], axi_rdata, axi_rresp, axi_rlast, $time);
                if (beat == 0 && stall == 0 && cycles - accepted > 3)
                    $fatal(1, "FAIL memory first beat latency %0d", cycles-accepted);
                if (beat > 0 && stall == 0 && cycles != previous + 1)
                    $fatal(1, "FAIL burst bubble beat=%0d", beat);
                previous = cycles;
                checks = checks + 1;
                @(negedge clk);
                if ((stall != 0) && beat < len) begin
                    axi_rready = 0;
                    repeat (stall) @(negedge clk);
                    axi_rready = 1;
                end
            end
            axi_rready = 0;
        end
    endtask
    task automatic write_check(input [31:0] addr, input [2:0] size,
        input integer len, input [7:0] strb, input [63:0] data);
        integer beat;
        integer lane;
        integer idx;
        reg [63:0] value;
        begin
            @(negedge clk);
            axi_awaddr = addr;
            axi_awsize = size;
            axi_awlen = 8'(len);
            axi_awid = 4'h5;
            axi_awburst = 1;
            axi_awvalid = 1;
            // W may arrive before AW; the endpoint must not lose the held payload.
            axi_wvalid = 1;
            axi_wdata = data;
            axi_wstrb = strb;
            axi_wlast = (len == 0);
            do @(posedge clk); while (!axi_awready);
            @(negedge clk);
            axi_awvalid = 0;
            for (beat = 0; beat <= len; beat = beat + 1) begin
                value = data + 64'(beat);
                axi_wvalid = 1;
                axi_wdata = value;
                axi_wlast = (beat == len);
                do @(posedge clk); while (!axi_wready);
                @(negedge clk);
                axi_wvalid = 0;
                if (beat < len) repeat (beat % 3) @(negedge clk);
            end
            // B is deliberately stalled to verify response persistence.
            repeat (3) @(negedge clk);
            axi_bready = 1;
            do @(posedge clk); while (!axi_bvalid);
            if (axi_bid !== 4'h5 || axi_bresp !== 2'b10)
                $fatal(1, "FAIL write response %h id=%h", axi_bresp, axi_bid);
            checks = checks + 1;
            @(negedge clk);
            axi_bready = 0;
        end
    endtask
    integer size;
    integer strb;
    reg [4095:0] image_path;
    initial begin
        $readmemh("verif/unit/bus_rom/init.hex", reference);
        if (!$value$plusargs("ROM_HEX=%s", image_path)) begin
            $readmemh("verif/unit/bus_rom/init.hex", dut.u_memory.memory_r);
        end
        repeat (3) @(negedge clk);
        rst_n = 1;
        // MEM-01/MEM-05: initialized contents, all read sizes and final word.
        for (size = 0; size <= 3; size = size + 1)
            read_check(BASE + (32'd1 << size), 3'(size), 0, 0);
        read_check(BASE + 8, 2, 0, 2);
        read_check(BASE + 32'd16376, 2, 0, 0);
        // MEM-02: ROM writes drain every W beat, report SLVERR, preserve contents.
        write_check(BASE, 2, 0, 8'hff, 64'hf0f0f0f0f0f0f0f0);
        write_check(BASE, 3, 3, 8'hff, 64'hf0f0f0f0f0f0f0f0);
        read_check(BASE, 3, 3, 0);
        read_check(BASE, 3, 3, 2);
        // Reset drops control immediately and leaves initialized/written data intact.
        @(negedge clk); axi_araddr = BASE; axi_arlen = 3; axi_arsize = 3; axi_arvalid = 1;
        do @(posedge clk); while (!axi_arready);
        @(negedge clk); axi_arvalid = 0;
        #1 rst_n = 0;
        #1;
        if (axi_rvalid !== 0 || axi_bvalid !== 0)
            $fatal(1, "FAIL asynchronous reset did not cancel response");
        repeat (3) @(negedge clk);
        rst_n = 1;
        read_check(BASE, 3, 3, 0);
        $display("PASS memory checks=%0d", checks);
        $finish;
    end
endmodule
