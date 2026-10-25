`timescale 1ns/1ps

module tb_yolo_uart_two_regions;
    reg clk_i = 1'b0;
    reg rst_n_i = 1'b0;
    reg uart_rx_i = 1'b1;
    always #3.333 clk_i = !clk_i;

    wire tx_valid_w;
    wire [7:0] tx_data_w;
    wire busy_w, ready_w, error_w;
    wire [31:0] base_w, size_w, received_w;
    wire [3:0] awid_w;
    wire [31:0] awaddr_w;
    wire [7:0] awlen_w;
    wire [2:0] awsize_w;
    wire [1:0] awburst_w;
    wire awvalid_w;
    wire [255:0] wdata_w;
    wire [31:0] wstrb_w;
    wire wlast_w, wvalid_w, bready_w;
    reg bvalid_r = 1'b0;
    reg [3:0] bid_r = 4'd0;
    reg [31:0] pending_addr_r = 32'd0;
    reg [255:0] first_data_r, second_data_r;
    integer writes_r = 0;
    reg [7:0] replies_r [0:31];
    integer reply_count_r = 0;

    edrv32_yolo_uart_boot #(.CLK_HZ(150000000), .UART_BAUD(15000000))
    dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .enable_i(1'b1),
        .uart_rx_i(uart_rx_i),
        .tx_valid_o(tx_valid_w), .tx_ready_i(1'b1),
        .tx_data_o(tx_data_w),
        .transfer_busy_o(busy_w), .model_ready_o(ready_w),
        .model_error_o(error_w), .model_base_o(base_w),
        .model_size_o(size_w), .received_bytes_o(received_w),
        .m_awid_o(awid_w), .m_awaddr_o(awaddr_w),
        .m_awlen_o(awlen_w), .m_awsize_o(awsize_w),
        .m_awburst_o(awburst_w), .m_awvalid_o(awvalid_w),
        .m_awready_i(1'b1),
        .m_wdata_o(wdata_w), .m_wstrb_o(wstrb_w),
        .m_wlast_o(wlast_w), .m_wvalid_o(wvalid_w),
        .m_wready_i(1'b1),
        .m_bid_i(bid_r), .m_bresp_i(2'b00),
        .m_bvalid_i(bvalid_r), .m_bready_o(bready_w)
    );

    always @(posedge clk_i) begin
        if (tx_valid_w) begin
            if (reply_count_r < 32)
                replies_r[reply_count_r] <= tx_data_w;
            reply_count_r <= reply_count_r + 1;
        end
        if (awvalid_w) begin
            if (awlen_w != 8'd0 || awsize_w != 3'd5 ||
                awburst_w != 2'b01)
                $fatal(1, "unexpected AXI write geometry");
            pending_addr_r <= awaddr_w;
            bid_r <= awid_w;
        end
        if (wvalid_w) begin
            if (!wlast_w || wstrb_w != 32'hffff_ffff)
                $fatal(1, "unexpected AXI write data");
            if (writes_r == 0) begin
                if (pending_addr_r != 32'h0000_6000)
                    $fatal(1, "first DDR base mismatch");
                first_data_r <= wdata_w;
            end else if (writes_r == 1) begin
                if (pending_addr_r != 32'h0000_6020)
                    $fatal(1, "second DDR base mismatch");
                second_data_r <= wdata_w;
            end else
                $fatal(1, "unexpected third AXI write");
            writes_r <= writes_r + 1;
            bvalid_r <= 1'b1;
        end else if (bvalid_r && bready_w)
            bvalid_r <= 1'b0;
    end

    task automatic send_uart(input [7:0] value);
        integer bit_no;
        begin
            uart_rx_i = 1'b0;
            #66.667;
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                uart_rx_i = value[bit_no];
                #66.667;
            end
            uart_rx_i = 1'b1;
            #66.667;
        end
    endtask

    reg [7:0] transport_r [0:121];
    integer transport_fd, length, index;
    initial begin
        transport_fd = $fopen("sim/build/yolo_uart_smoke.ymod", "rb");
        if (transport_fd == 0)
            $fatal(1, "missing yolo_uart_smoke.ymod");
        length = $fread(transport_r, transport_fd);
        $fclose(transport_fd);
        if (length != 122)
            $fatal(1, "unexpected transport size %0d", length);
        repeat (8) @(negedge clk_i);
        rst_n_i = 1'b1;
        for (index = 0; index < length; index = index + 1)
            send_uart(transport_r[index]);
        wait (reply_count_r == 16);
        if (!ready_w || error_w || received_w != 32'd32)
            $fatal(1, "first image did not complete");
        transport_r[4] = 8'h20;
        for (index = 0; index < length; index = index + 1)
            send_uart(transport_r[index]);
        wait (reply_count_r == 32);
        if (!ready_w || error_w || received_w != 32'd32 ||
            base_w != 32'h0000_6020 || writes_r != 2)
            $fatal(1, "second image did not complete");
        for (index = 0; index < 32; index = index + 1)
            if (first_data_r[index*8 +: 8] !== ((index*7+3) & 8'hff) ||
                second_data_r[index*8 +: 8] !== ((index*7+3) & 8'hff))
                $fatal(1, "DDR write mismatch byte %0d", index);
        if (replies_r[0] !== "Y" || replies_r[1] !== "R" ||
            replies_r[8] !== "Y" || replies_r[9] !== "D" ||
            replies_r[16] !== "Y" || replies_r[17] !== "R" ||
            replies_r[24] !== "Y" || replies_r[25] !== "D")
            $fatal(1, "UART response mismatch");
        $display("tb_yolo_uart_two_regions PASS");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "UART two-region timeout replies=%0d writes=%0d boot=%0d dma=%0d done=%0d base=%h",
               reply_count_r, writes_r, dut.state_r, dut.u_dma.state_r,
               ready_w, base_w);
    end
endmodule
