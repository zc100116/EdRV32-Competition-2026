`timescale 1ns/1ps

module tb_render_cmd_fetch;
    localparam [31:0] LIST_BASE = 32'h0000_1000;
    reg clk;
    reg rst_n;
    reg start;
    wire start_ready;
    reg [31:0] list_base;
    reg [15:0] list_count;
    wire cmd_valid;
    reg cmd_ready;
    wire [511:0] cmd_data;
    wire [15:0] cmd_index;
    wire busy;
    wire done;
    wire error;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid;
    reg arready;
    reg [3:0] rid;
    reg [255:0] rdata;
    reg [1:0] rresp;
    reg rlast;
    reg rvalid;
    wire rready;

    reg [511:0] descriptors [0:3];
    reg inject_error;
    integer response_phase;
    integer response_index;
    integer received;
    integer ar_count;
    integer cycle_count;
    integer i;
    integer j;

    always #5 clk = ~clk;

    edrv32_render_cmd_fetch u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .cancel_i(1'b0),
        .start_ready_o(start_ready),
        .list_base_i(list_base), .list_count_i(list_count),
        .cmd_valid_o(cmd_valid), .cmd_ready_i(cmd_ready),
        .cmd_data_o(cmd_data), .cmd_index_o(cmd_index),
        .busy_o(busy), .done_o(done), .error_o(error),
        .m_arid_o(arid), .m_araddr_o(araddr), .m_arlen_o(arlen),
        .m_arsize_o(arsize), .m_arburst_o(arburst),
        .m_arvalid_o(arvalid), .m_arready_i(arready),
        .m_rid_i(rid), .m_rdata_i(rdata), .m_rresp_i(rresp),
        .m_rlast_i(rlast), .m_rvalid_i(rvalid), .m_rready_o(rready)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        list_base = LIST_BASE;
        list_count = 16'd0;
        cmd_ready = 1'b0;
        arready = 1'b0;
        rid = 4'h5;
        rdata = 256'b0;
        rresp = 2'b0;
        rlast = 1'b0;
        rvalid = 1'b0;
        inject_error = 1'b0;
        response_phase = 0;
        response_index = 0;
        received = 0;
        ar_count = 0;
        cycle_count = 0;
        for (i = 0; i < 4; i = i + 1)
            for (j = 0; j < 16; j = j + 1)
                descriptors[i][j*32 +: 32] =
                    32'h9300_0000 + i*256 + j;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        list_count = 16'd4;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || received != 4 || ar_count != 4)
            $fatal(1, "normal list failed count=%0d ar=%0d error=%b",
                   received, ar_count, error);

        @(negedge clk);
        received = 0;
        ar_count = 0;
        inject_error = 1'b1;
        list_count = 16'd1;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (!error || received != 0 || ar_count != 1)
            $fatal(1, "read error not blocked");

        @(negedge clk);
        inject_error = 1'b0;
        list_base = LIST_BASE + 32'd32;
        start = 1'b1;
        @(posedge clk);
        #1;
        if (!done || !error || busy)
            $fatal(1, "misaligned command list not rejected");
        $display("RENDER_CMD_FETCH_PASS commands=4 fault=1 alignment=1");
        $finish;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            cmd_ready = $urandom_range(0, 3) != 0;
            arready = (response_phase == 0) &&
                      ($urandom_range(0, 3) != 0);
            rvalid = (response_phase != 0) &&
                     ($urandom_range(0, 3) != 0);
            rid = 4'h5;
            if (response_phase != 0) begin
                rdata = response_phase == 1 ?
                        descriptors[response_index][255:0] :
                        descriptors[response_index][511:256];
                rlast = response_phase == 2;
                rresp = (inject_error && response_phase == 2) ?
                        2'b10 : 2'b00;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            if (arvalid && arready) begin
                if (arid != 4'h5 || arlen != 8'd1 ||
                    arsize != 3'd5 || arburst != 2'b01 ||
                    araddr != LIST_BASE + ar_count*64 ||
                    araddr[5:0] != 6'd0)
                    $fatal(1, "invalid command AXI request addr=%h", araddr);
                response_index = ar_count;
                response_phase = 1;
                ar_count = ar_count + 1;
            end
            if (rvalid && rready) begin
                if (response_phase == 1)
                    response_phase = 2;
                else
                    response_phase = 0;
            end
            if (cmd_valid && cmd_ready) begin
                if (cmd_index !== received ||
                    cmd_data !== descriptors[received])
                    $fatal(1, "command mismatch index=%0d", received);
                received = received + 1;
            end
            if (cycle_count > 2000)
                $fatal(1, "command fetch timeout");
        end
    end
endmodule
