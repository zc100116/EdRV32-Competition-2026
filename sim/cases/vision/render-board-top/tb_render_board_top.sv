`timescale 1ns/1ps

module tb_render_board_top;
    reg clk, rst_n;
    reg start;
    wire cmd_done, cmd_error, apb_done, apb_error;
    wire [3:0] awid, bid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire [3:0] awqos;
    wire awvalid, awready;
    wire [255:0] wdata;
    wire [31:0] wstrb;
    wire wlast, wvalid, wready;
    wire [1:0] bresp;
    wire bvalid, bready;
    wire [31:0] paddr, pwdata, prdata;
    wire [3:0] pstrb;
    wire psel, penable, pwrite, pready, pslverr;
    wire irq;
    integer cycles;

    always #5 clk = ~clk;

    edrv32_pango_200h_render_demo_cmd_writer u_cmd (
        .clk_i(clk), .rst_n_i(rst_n), .start_i(start),
        .done_o(cmd_done), .error_o(cmd_error),
        .m_awid_o(awid), .m_awaddr_o(awaddr),
        .m_awlen_o(awlen), .m_awsize_o(awsize),
        .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid), .m_awready_i(awready),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb),
        .m_wlast_o(wlast), .m_wvalid_o(wvalid),
        .m_wready_i(wready),
        .m_bid_i(bid), .m_bresp_i(bresp),
        .m_bvalid_i(bvalid), .m_bready_o(bready)
    );

    axi256_mem_model #(.WORDS(1024)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(awid), .awaddr_i(awaddr),
        .awlen_i(awlen), .awsize_i(awsize),
        .awburst_i(awburst),
        .awvalid_i(awvalid), .awready_o(awready),
        .wdata_i(wdata), .wstrb_i(wstrb),
        .wlast_i(wlast), .wvalid_i(wvalid),
        .wready_o(wready), .bid_o(bid), .bresp_o(bresp),
        .bvalid_o(bvalid), .bready_i(bready),
        .arid_i(4'd0), .araddr_i(32'd0),
        .arlen_i(8'd0), .arsize_i(3'd5),
        .arburst_i(2'b01), .arvalid_i(1'b0),
        .arready_o(), .rid_o(), .rdata_o(),
        .rresp_o(), .rlast_o(), .rvalid_o(),
        .rready_i(1'b0)
    );

    edrv32_pango_200h_render_demo_apb u_apb (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(cmd_done && !cmd_error),
        .done_o(apb_done), .error_o(apb_error),
        .paddr_o(paddr), .psel_o(psel),
        .penable_o(penable), .pwrite_o(pwrite),
        .pwdata_o(pwdata), .pstrb_o(pstrb),
        .pready_i(pready), .prdata_i(prdata),
        .pslverr_i(pslverr)
    );

    edrv32_render_frame_ctrl u_ctrl (
        .clk_i(clk), .rst_n_i(rst_n),
        .paddr_i(paddr), .psel_i(psel), .penable_i(penable),
        .pwrite_i(pwrite), .pwdata_i(pwdata), .pstrb_i(pstrb),
        .pready_o(pready), .prdata_o(prdata),
        .pslverr_o(pslverr), .irq_o(irq),
        .base_valid_i(1'b0), .base_buffer_i(2'd0),
        .base_addr_i(32'd0), .base_stride_i(32'd0),
        .base_release_valid_o(), .base_release_buffer_o(),
        .display_valid_o(), .display_ready_i(1'b0),
        .display_token_o(), .display_base_o(),
        .display_retire_valid_i(1'b0),
        .display_retire_token_i(3'd0),
        .draw_start_o(), .draw_ready_i(1'b0),
        .draw_list_base_o(), .draw_list_count_o(),
        .draw_done_i(1'b0), .draw_error_i(1'b0),
        .compose_start_o(), .compose_ready_i(1'b0),
        .compose_base_o(), .compose_base_stride_o(),
        .compose_front_o(), .compose_front_stride_o(),
        .compose_target_o(), .compose_target_stride_o(),
        .compose_width_o(), .compose_height_o(),
        .compose_done_i(1'b0), .compose_error_i(1'b0)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        cycles = 0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        start = 1'b1;
        wait(apb_done);
        #1;
        if (cmd_error || apb_error ||
            !u_ctrl.front_enable_r ||
            !u_ctrl.command_pending_r ||
            u_ctrl.command_base_r != 32'h0000_1000 ||
            u_ctrl.command_count_r != 16'd2)
            $fatal(1,"board bootstrap APB submission failed");
        if (u_mem.store[32'h1000 >> 5][7:0] !== 8'h02 ||
            u_mem.store[(32'h1000 >> 5)+2][7:0] !== 8'h04 ||
            u_mem.store[(32'h1000 >> 5)+2][63:32] !==
                32'h0311_3000)
            $fatal(1,"board bootstrap DDR commands failed");
        $display("RENDER_BOARD_BOOT_PASS cycles=%0d",cycles);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (cycles > 1000)
                $fatal(1,"board bootstrap timeout");
        end
    end
endmodule
