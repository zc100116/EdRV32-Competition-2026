`timescale 1ns/1ps

module tb_yolo_serial_dma;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg start = 0;
    reg [31:0] base = 32'h0000_1fe0;
    reg [31:0] size = 32'd1056;
    reg [31:0] expected_crc = 0;
    reg rx_valid = 0;
    reg [7:0] rx_data = 0;
    reg rx_error = 0;
    wire tx_valid;
    wire [7:0] tx_data;
    wire busy, done, error;
    wire [31:0] received_bytes;
    wire [15:0] next_seq;
    wire [3:0] awid, bid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst, bresp;
    wire awvalid, awready, wlast, wvalid, wready, bvalid, bready;
    wire [255:0] wdata;
    wire [31:0] wstrb;
    reg [7:0] memory [0:16383];
    reg [31:0] write_addr = 0;
    reg [7:0] write_count = 0;
    reg [7:0] write_len = 0;
    reg write_active = 0;
    reg bvalid_r = 0;
    reg [1:0] bresp_r = 0;
    reg inject_b_error = 0;
    integer bursts = 0;
    integer writes = 0;
    integer cycle_count = 0;
    reg [7:0] response [0:7];
    integer response_index = 0;
    integer response_count = 0;
    integer i;

    assign awready = !write_active && !bvalid_r;
    assign wready = write_active && cycle_count % 5 != 0;
    assign bvalid = bvalid_r;
    assign bresp = bresp_r;
    assign bid = 4'hb;

    edrv32_yolo_serial_dma dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(),
        .base_i(base), .size_i(size), .expected_crc_i(expected_crc),
        .rx_valid_i(rx_valid), .rx_data_i(rx_data),
        .rx_frame_error_i(rx_error),
        .tx_valid_o(tx_valid), .tx_ready_i(1'b1), .tx_data_o(tx_data),
        .busy_o(busy), .done_o(done), .error_o(error),
        .received_bytes_o(received_bytes), .next_seq_o(next_seq),
        .m_awid_o(awid), .m_awaddr_o(awaddr), .m_awlen_o(awlen),
        .m_awsize_o(awsize), .m_awburst_o(awburst),
        .m_awvalid_o(awvalid), .m_awready_i(awready),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb),
        .m_wlast_o(wlast), .m_wvalid_o(wvalid), .m_wready_i(wready),
        .m_bid_i(bid), .m_bresp_i(bresp),
        .m_bvalid_i(bvalid), .m_bready_o(bready)
    );

    function automatic [31:0] crc_byte(input [31:0] crc,
                                        input [7:0] data);
        reg [31:0] value;
        integer j;
        begin
            value = crc ^ {24'd0, data};
            for (j = 0; j < 8; j = j + 1)
                value = value[0] ? (value >> 1) ^ 32'hedb8_8320 :
                                   (value >> 1);
            crc_byte = value;
        end
    endfunction

    function automatic [7:0] model_byte(input integer index);
        model_byte = (index * 37 + (index >> 3) + 13) & 8'hff;
    endfunction

    function automatic [7:0] hex_digit(input [3:0] value);
        hex_digit = value < 10 ? "0" + value : "A" + value - 10;
    endfunction

    task automatic send_byte(input [7:0] value);
        begin
            @(negedge clk);
            rx_data = value;
            rx_valid = 1;
            @(negedge clk);
            rx_valid = 0;
        end
    endtask

    task automatic send_packet(input integer seq,
                               input integer length,
                               input bit bad_crc);
        reg [31:0] crc;
        reg [7:0] value;
        integer j;
        begin
            crc = 32'hffff_ffff;
            send_byte(8'h59);
            send_byte(8'h4d);
            value = seq[7:0]; send_byte(value); crc = crc_byte(crc, value);
            value = seq[15:8]; send_byte(value); crc = crc_byte(crc, value);
            value = length[7:0]; send_byte(value); crc = crc_byte(crc, value);
            value = length[15:8]; send_byte(value); crc = crc_byte(crc, value);
            for (j = 0; j < length; j = j + 1) begin
                value = model_byte(seq * 1024 + j);
                send_byte(value);
                crc = crc_byte(crc, value);
            end
            crc = ~crc;
            if (bad_crc)
                crc = crc ^ 32'h0000_0001;
            for (j = 0; j < 4; j = j + 1)
                send_byte(crc[j*8 +: 8]);
        end
    endtask

    task automatic wait_reply(input integer count,
                              input [7:0] code,
                              input integer next);
        integer timeout;
        begin
            timeout = 0;
            while (response_count < count && timeout < 10000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (response_count != count || response[0] !== "Y" ||
                response[1] !== code ||
                response[2] !== hex_digit(next[15:12]) ||
                response[3] !== hex_digit(next[11:8]) ||
                response[4] !== hex_digit(next[7:4]) ||
                response[5] !== hex_digit(next[3:0]) ||
                response[6] !== 8'h0d || response[7] !== 8'h0a) begin
                $display("reply mismatch count=%0d code=%h seq=%c%c%c%c",
                         response_count, response[1], response[2],
                         response[3], response[4], response[5]);
                $fatal(1);
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count <= cycle_count + 1;
            if (tx_valid) begin
                response[response_index] <= tx_data;
                if (response_index == 7) begin
                    response_index <= 0;
                    response_count <= response_count + 1;
                end else
                    response_index <= response_index + 1;
            end
            if (awvalid && awready) begin
                if (awsize != 3'd5 || awburst != 2'b01 || awid != 4'hb ||
                    awaddr[4:0] != 0 || awlen > 8'd15 ||
                    {1'b0, awaddr[11:0]} + ({5'd0, awlen} + 13'd1) * 13'd32 >
                    13'd4096)
                    $fatal(1, "invalid AXI burst addr=%h len=%0d", awaddr, awlen);
                write_addr <= awaddr;
                write_len <= awlen;
                write_count <= 0;
                write_active <= 1;
                bursts <= bursts + 1;
            end
            if (wvalid && wready) begin
                if (wstrb !== 32'hffff_ffff ||
                    wlast !== (write_count == write_len))
                    $fatal(1, "invalid WLAST/WSTRB");
                for (integer lane = 0; lane < 32; lane = lane + 1)
                    memory[write_addr + write_count*32 + lane] <=
                        wdata[lane*8 +: 8];
                writes <= writes + 1;
                if (wlast) begin
                    write_active <= 0;
                    bvalid_r <= 1;
                    bresp_r <= inject_b_error ? 2'b10 : 2'b00;
                end else
                    write_count <= write_count + 1;
            end
            if (bvalid && bready)
                bvalid_r <= 0;
        end
    end

    initial begin
        expected_crc = 32'hffff_ffff;
        for (i = 0; i < 1056; i = i + 1)
            expected_crc = crc_byte(expected_crc, model_byte(i));
        expected_crc = ~expected_crc;
        repeat (5) @(negedge clk);
        rst_n = 1;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        wait_reply(1, 8'h52, 0);

        send_packet(0, 1024, 1);
        wait_reply(2, 8'h4e, 0);
        if (writes != 0 || received_bytes != 0)
            $fatal(1, "bad packet reached DDR");
        send_packet(0, 1024, 0);
        wait_reply(3, 8'h41, 1);
        send_packet(0, 1024, 0);
        wait_reply(4, 8'h41, 1);
        if (received_bytes != 1024 || writes != 32)
            $fatal(1, "duplicate packet wrote twice");
        send_packet(1, 32, 0);
        wait_reply(5, 8'h44, 2);
        if (!done || error || received_bytes != 1056 ||
            bursts != 4 || writes != 33)
            $fatal(1, "completion mismatch bursts=%0d writes=%0d",
                   bursts, writes);
        for (i = 0; i < 1056; i = i + 1)
            if (memory['h1fe0+i] !== model_byte(i))
                $fatal(1, "DDR byte mismatch at %0d", i);
        send_packet(1, 32, 0);
        wait_reply(6, 8'h44, 2);
        if (writes != 33)
            $fatal(1, "final packet retry wrote twice");

        // A write response error must never acknowledge a packet.
        @(negedge clk);
        base = 32'h3000;
        size = 32'd32;
        expected_crc = 32'hffff_ffff;
        for (i = 0; i < 32; i = i + 1)
            expected_crc = crc_byte(expected_crc, model_byte(i));
        expected_crc = ~expected_crc;
        inject_b_error = 1;
        start = 1;
        @(negedge clk); start = 0;
        wait_reply(7, 8'h52, 0);
        send_packet(0, 32, 0);
        wait_reply(8, 8'h45, 0);
        if (!error || done || received_bytes != 0)
            $fatal(1, "AXI response error was not fatal");
        $display("tb_yolo_serial_dma PASS");
        $finish;
    end
endmodule
