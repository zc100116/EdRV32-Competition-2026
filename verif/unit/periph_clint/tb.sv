// File: tb.sv
// Spec: sys-subsys-testplan CL-01--CL-05 / PL-01--PL-05.
// Description: Self-checking AXI register and interrupt tests.
// Clock: clk_sys plus asynchronous source clock for PLIC.
module tb;
    localparam [31:0] BASE = 32'h20000000;
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
    wire [63:0] mtime;
    wire mtip;
    wire msip;
    edrv32_periph_clint u_dut (
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
        .mtime_o(mtime),
        .irq_mtip_o(mtip),
        .irq_msip_o(msip)
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
    task wr(input [31:0] offset, input [31:0] value,
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
    task rd(input [31:0] offset, output [31:0] value,
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
        read_snapshot = mtime;
        #1;
        @(negedge clk);
        axi_arvalid_i = 0;
        held_data = axi_rdata_o;
        repeat (3) begin
            tick();
            check(axi_rvalid_o && axi_rid_o == 4'hD && axi_rdata_o === held_data &&
                  axi_rresp_o == response && axi_rlast_o == (len == 0),
                  "R stable during backpressure");
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
    // Cycle reference checks CL-01/02/03 including low-half carry on a write.
    reg [63:0] ref_time = 0;
    reg [63:0] ref_cmp = 64'hFFFFFFFFFFFFFFFF;
    reg ref_msip = 0;
    reg ref_mtip = 0;
    reg [31:0] ref_write_addr;
    reg ref_write_legal;
    reg [31:0] ref_write_data;
    always @(posedge clk) begin
        if (!rst_n) begin
            ref_time = 0;
            ref_cmp = 64'hFFFFFFFFFFFFFFFF;
            ref_msip = 0;
            ref_mtip = 0;
        end else begin
            ref_mtip = ref_time >= ref_cmp;
            ref_time = ref_time + 1;
            if (axi_awvalid_i && axi_awready_o) begin
                ref_write_addr = axi_awaddr_i - BASE;
                ref_write_legal = axi_awlen_i == 0 && axi_awsize_i == 2 &&
                                  axi_awaddr_i[1:0] == 0;
            end
            if (axi_wvalid_i && axi_wready_o && ref_write_legal) begin
                ref_write_data = ref_write_addr[2] ? axi_wdata_i[63:32] : axi_wdata_i[31:0];
                case (ref_write_addr)
                    'h0000: ref_msip = ref_write_data[0];
                    'h4000: ref_cmp[31:0] = ref_write_data;
                    'h4004: ref_cmp[63:32] = ref_write_data;
                    'hBFF8: ref_time[31:0] = ref_write_data;
                    'hBFFC: ref_time[63:32] = ref_write_data;
                    default: begin end
                endcase
            end
        end
        #1;
        check(mtime === ref_time, "CL-01/02 timer cycle reference");
        check(mtip === ref_mtip, "CL-03 registered timer comparison");
        check(msip === ref_msip, "CL-04 software interrupt");
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
        reset_device();
        check(!mtip && !msip, "CL-03/04 reset interrupts");
        rd('h4000, value); check(value == 'hFFFFFFFF, "cmp low reset");
        rd('h4004, value); check(value == 'hFFFFFFFF, "cmp high reset");
        repeat (8) tick();
        rd('hBFF8, value); check(value == read_snapshot[31:0], "CL-01 mtime low read");
        rd('hBFFC, value); check(value == read_snapshot[63:32], "CL-01 mtime high read");
        wr('hBFFC, 3);
        wr('hBFF8, 'hFFFFFFF8);
        repeat (20) tick();
        check(mtime[63:32] == 4, "CL-02 low carry into high");
        wr('hBFFC, 0);
        wr('hBFF8, 0);
        wr('h4004, 0);
        target = mtime[31:0] + 80;
        wr('h4000, target);
        wait (mtime == {32'd0, target - 32'd1});
        #1; check(!mtip, "CL-03 cmp minus one");
        tick(); check(mtime == {32'd0, target} && !mtip, "CL-03 equality pipeline");
        tick(); check(mtip, "CL-03 comparator registered output");
        wr('h0000, 1); check(msip, "CL-04 set");
        wr('h0000, 0); check(!msip, "CL-04 clear");
        for (integer s = 0; s < 8; s++) begin
            if (s != 2) begin
                wr('h0000, 1, 0, 3'(s));
                rd('h0000, value, 0, 3'(s));
                check(!msip, "CL-05 rejected size no side effect");
            end
        end
        wr('h0000, 1, 3); rd('h0000, value, 3);
        wr('h0000, 1, 255); rd('h0000, value, 255);
        check(!msip, "CL-05 burst no side effect");
        wr('h0001, 1); rd('h0001, value);
        wr('h0010, 1); rd('h0010, value); check(value == 0, "unlisted offset");
        $display("PASS CL-01 CL-02 CL-03 CL-04 CL-05");
        $finish;
    end
    reg [31:0] value;
    reg [31:0] target;
    initial begin
        #200000;
        $fatal(1, "FAIL timeout");
    end
endmodule
