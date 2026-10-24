`timescale 1ns/1ps

module tb_yolo_quant_cfg_dma;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg enable = 1;
    reg [4:0] block = 0;
    reg [4:0] channel = 0;
    reg cfg_ready = 1;
    reg lut_enable = 1;
    reg [7:0] lut_index = 0;
    reg lut_ready = 0;
    wire cfg_valid, lut_valid, owner, error;
    wire [31:0] bias;
    wire [15:0] multiplier;
    wire [5:0] shift;
    wire [7:0] zero_point, lut_data;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid, rready;
    reg [255:0] memory [0:191];
    reg read_active = 0;
    reg [31:0] read_addr = 0;
    reg [4:0] read_index = 0;
    reg inject_error = 0;
    integer cycles = 0;
    integer previous_cfg_cycle = -1;
    integer cfg_count = 0;
    integer lut_count = 0;
    integer ar_count = 0;
    integer b, c, i;
    wire arready = !read_active && cycles % 4 == 0;
    wire rvalid = read_active && cycles % 3 != 0;
    wire [255:0] rdata = memory[(read_addr >> 5) + read_index];
    wire [1:0] rresp = inject_error && read_index == 0 ? 2'b10 : 2'b00;
    wire rlast = read_index == 15;
    wire lut_accept_w = lut_ready && cycles % 5 != 0;

    edrv32_yolo_quant_cfg_dma dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .enable_i(enable), .cfg_base_i(32'h1000),
        .cfg_block_i(block), .cfg_phase_i(cfg_ready),
        .lut_enable_i(lut_enable),
        .cfg_channel_i(channel),
        .cfg_ready_i(cfg_ready), .cfg_valid_o(cfg_valid),
        .cfg_bias_o(bias), .cfg_multiplier_o(multiplier),
        .cfg_shift_o(shift), .cfg_zero_point_o(zero_point),
        .lut_index_i(lut_index), .lut_ready_i(lut_accept_w),
        .lut_valid_o(lut_valid), .lut_data_o(lut_data),
        .axi_owner_o(owner), .error_o(error),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst),
        .m_arvalid_o(arvalid), .m_arready_i(arready),
        .m_rid_i(4'hd), .m_rdata_i(rdata),
        .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid), .m_rready_o(rready)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (arvalid && arready) begin
                if (!owner || arid != 4'hd || arlen != 15 ||
                    arsize != 3'd5 || arburst != 2'b01 ||
                    araddr != 32'h1000 + (block << 9))
                    $fatal(1, "incorrect quant AR request");
                read_addr <= araddr;
                read_index <= 0;
                read_active <= 1;
                ar_count <= ar_count + 1;
            end
            if (rvalid && rready) begin
                if (rlast)
                    read_active <= 0;
                else
                    read_index <= read_index + 1;
            end
            if (cfg_valid && cfg_ready) begin
                if (channel != 0 && cycles != previous_cfg_cycle + 1)
                    $fatal(1, "quant config stream stalled at channel %0d",
                           channel);
                previous_cfg_cycle <= cycles;
                if (bias !== block * 1000 + channel ||
                    multiplier !== block * 100 + channel + 1 ||
                    shift !== channel % 5 + 1 || zero_point !== 0)
                    $fatal(1, "channel record mismatch b=%0d c=%0d",
                           block, channel);
                cfg_count <= cfg_count + 1;
                if (channel == 31) begin
                    if (lut_enable) begin
                        cfg_ready <= 0;
                        lut_ready <= 1;
                        lut_index <= 0;
                    end else begin
                        block <= block + 1;
                        channel <= 0;
                        inject_error <= 1;
                    end
                end else
                    channel <= channel + 1;
            end
            if (lut_valid && lut_accept_w) begin
                if (lut_data !== ((block * 17 + lut_index) & 8'hff))
                    $fatal(1, "LUT mismatch b=%0d i=%0d", block, lut_index);
                lut_count <= lut_count + 1;
                if (lut_index == 255) begin
                    lut_ready <= 0;
                    block <= block + 1;
                    channel <= 0;
                    cfg_ready <= 1;
                    if (block == 1)
                        lut_enable <= 0;
                end else
                    lut_index <= lut_index + 1;
            end
        end
    end

    initial begin
        for (b = 0; b < 4; b = b + 1) begin
            for (i = 0; i < 16; i = i + 1)
                memory[128 + b*16 + i] = 0;
            for (c = 0; c < 32; c = c + 1)
                memory[128 + b*16 + c/4][(c%4)*64 +: 64] =
                    {8'd0, 8'(c%5+1), 16'(b*100+c+1), 32'(b*1000+c)};
            for (i = 0; i < 256; i = i + 1)
                memory[128 + b*16 + 8 + i/32][(i%32)*8 +: 8] =
                    (b*17+i) & 8'hff;
        end
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (error);
        #1;
        if (cfg_count != 96 || lut_count != 512 || ar_count != 4 || owner)
            $fatal(1, "quant DMA counts mismatch cfg=%0d lut=%0d ar=%0d",
                   cfg_count, lut_count, ar_count);
        $display("tb_yolo_quant_cfg_dma PASS: LUT, linear, AXI error");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "quant DMA timeout block=%0d channel=%0d", block, channel);
    end
endmodule
