`timescale 1ns/1ps

module tb_vision_telemetry;

    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;

    reg rst_n_i = 1'b0;
    reg [4:0] mode_i = 5'd3;
    reg source_frame_i = 1'b0;
    reg [31:0] source_drop_count_i = 32'b0;
    reg geometry_start_i = 1'b0;
    reg geometry_done_i = 1'b0;
    reg geometry_error_i = 1'b0;
    reg [2:0] geometry_phase_i = 3'b0;
    reg display_flip_i = 1'b0;
    reg [31:0] reader_frame_count_i = 32'b0;
    reg [31:0] underflow_count_i = 32'b0;
    reg [31:0] cam0_frame_count_i = 32'b0;
    reg [31:0] cam1_frame_count_i = 32'b0;
    reg [31:0] pixel_frame_count_i = 32'b0;
    reg [31:0] replaced_frame_count_i = 32'b0;
    reg input_stream_stall_i = 1'b0;
    reg output_stream_stall_i = 1'b0;
    reg camera_w_stall_i = 1'b0;
    reg write_owner_valid_i = 1'b0;
    reg write_owner_geometry_i = 1'b0;
    reg mux_eof_i = 1'b0;
    reg [31:0] unpack_frame_count_i = 32'b0;
    reg [31:0] point_frame_count_i = 32'b0;
    reg [31:0] spatial_frame_count_i = 32'b0;
    reg mux_error_i = 1'b0;
    reg pixel_cfg_pending_i = 1'b0;
    reg writer_active_i = 1'b0;
    reg mux_valid_i = 1'b0;
    reg pixel_valid_i = 1'b0;
    reg cam0_overflow_i = 1'b0;
    reg cam1_overflow_i = 1'b0;
    reg writer_error_i = 1'b0;
    reg active_camera_i = 1'b0;
    reg rd_arvalid_i = 1'b0;
    reg rd_arready_i = 1'b0;
    reg [7:0] rd_arlen_i = 8'd3;
    reg rd_rvalid_i = 1'b0;
    reg rd_rready_i = 1'b0;
    reg wr_awvalid_i = 1'b0;
    reg wr_awready_i = 1'b0;
    reg wr_wvalid_i = 1'b0;
    reg wr_wready_i = 1'b0;
    reg wr_bvalid_i = 1'b0;
    reg wr_bready_i = 1'b0;
    wire uart_tx_o;

    edrv32_vision_telemetry #(
        .CLK_HZ(1000000),
        .BAUD(100000),
        .REPORT_CYCLES(30000)
    ) dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .mode_i(mode_i),
        .source_frame_i(source_frame_i),
        .source_drop_count_i(source_drop_count_i),
        .geometry_start_i(geometry_start_i),
        .geometry_done_i(geometry_done_i),
        .geometry_error_i(geometry_error_i),
        .geometry_phase_i(geometry_phase_i),
        .display_flip_i(display_flip_i),
        .reader_frame_count_i(reader_frame_count_i),
        .underflow_count_i(underflow_count_i),
        .cam0_frame_count_i(cam0_frame_count_i),
        .cam1_frame_count_i(cam1_frame_count_i),
        .pixel_frame_count_i(pixel_frame_count_i),
        .replaced_frame_count_i(replaced_frame_count_i),
        .input_stream_stall_i(input_stream_stall_i),
        .output_stream_stall_i(output_stream_stall_i),
        .camera_w_stall_i(camera_w_stall_i),
        .write_owner_valid_i(write_owner_valid_i),
        .write_owner_geometry_i(write_owner_geometry_i),
        .mux_eof_i(mux_eof_i),
        .unpack_frame_count_i(unpack_frame_count_i),
        .point_frame_count_i(point_frame_count_i),
        .spatial_frame_count_i(spatial_frame_count_i),
        .mux_error_i(mux_error_i),
        .pixel_cfg_pending_i(pixel_cfg_pending_i),
        .writer_active_i(writer_active_i),
        .mux_valid_i(mux_valid_i),
        .pixel_valid_i(pixel_valid_i),
        .cam0_overflow_i(cam0_overflow_i),
        .cam1_overflow_i(cam1_overflow_i),
        .writer_error_i(writer_error_i),
        .active_camera_i(active_camera_i),
        .rd_arvalid_i(rd_arvalid_i), .rd_arready_i(rd_arready_i),
        .rd_arlen_i(rd_arlen_i),
        .rd_rvalid_i(rd_rvalid_i), .rd_rready_i(rd_rready_i),
        .wr_awvalid_i(wr_awvalid_i), .wr_awready_i(wr_awready_i),
        .wr_wvalid_i(wr_wvalid_i), .wr_wready_i(wr_wready_i),
        .wr_bvalid_i(wr_bvalid_i), .wr_bready_i(wr_bready_i),
        .uart_tx_o(uart_tx_o)
    );

    reg [7:0] line_r [0:425];
    reg [31:0] field_r [0:46];
    integer line_len_r = 0;
    integer line_count_r = 0;
    integer checks_r = 0;
    integer i;
    integer j;
    integer k;
    reg [7:0] received_byte_r;

    function [3:0] hex_value;
        input [7:0] character_i;
        begin
            if ((character_i >= "0") && (character_i <= "9"))
                hex_value = character_i - "0";
            else if ((character_i >= "A") && (character_i <= "F"))
                hex_value = character_i - "A" + 4'd10;
            else begin
                $fatal(1, "bad hex character %h", character_i);
                hex_value = 4'b0;
            end
        end
    endfunction

    task expect_field;
        input integer index_i;
        input [31:0] expected_i;
        begin
            checks_r = checks_r + 1;
            if (field_r[index_i] !== expected_i)
                $fatal(1, "field %0d got %0d expected %0d",
                    index_i, field_r[index_i], expected_i);
        end
    endtask

    initial begin : receive_uart
        forever begin
            @(negedge uart_tx_o);
            #50;
            if (uart_tx_o !== 1'b0)
                $fatal(1, "bad UART start bit");
            received_byte_r = 8'b0;
            for (i = 0; i < 8; i = i + 1) begin
                #100;
                received_byte_r[i] = uart_tx_o;
            end
            #100;
            if (uart_tx_o !== 1'b1)
                $fatal(1, "bad UART stop bit");
            if (line_len_r >= 426)
                $fatal(1, "UART line too long");
            line_r[line_len_r] = received_byte_r;
            line_len_r = line_len_r + 1;
            if (received_byte_r == 8'h0a) begin
                if (line_len_r != 426)
                    $fatal(1, "UART line length %0d", line_len_r);
                if (line_r[0] != "G" || line_r[1] != "," ||
                    line_r[424] != 8'h0d)
                    $fatal(1, "UART CSV framing error");
                for (j = 0; j < 47; j = j + 1) begin
                    field_r[j] = 32'b0;
                    for (k = 0; k < 8; k = k + 1)
                        field_r[j] = {field_r[j][27:0],
                            hex_value(line_r[2 + j * 9 + k])};
                    if (j < 46 && line_r[2 + j * 9 + 8] != ",")
                        $fatal(1, "UART separator error at %0d", j);
                end
                line_count_r = line_count_r + 1;
                line_len_r = 0;
            end
        end
    end

    task hold_phase;
        input [2:0] phase_i;
        input integer cycles_i;
        begin
            @(negedge clk_i);
            geometry_phase_i = phase_i;
            repeat (cycles_i) @(negedge clk_i);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        repeat (10) @(negedge clk_i);
        source_frame_i = 1'b1;
        geometry_start_i = 1'b1;
        @(negedge clk_i);
        source_frame_i = 1'b0;
        geometry_start_i = 1'b0;

        hold_phase(3'd5, 5);
        hold_phase(3'd1, 4);
        @(negedge clk_i);
        geometry_phase_i = 3'd2;
        rd_arvalid_i = 1'b1;
        rd_arready_i = 1'b1;
        rd_rready_i = 1'b1;
        @(negedge clk_i);
        rd_arvalid_i = 1'b0;
        rd_arready_i = 1'b0;
        repeat (5) @(negedge clk_i);
        rd_rready_i = 1'b0;
        hold_phase(3'd3, 8);
        hold_phase(3'd4, 3);
        wr_wvalid_i = 1'b1;
        write_owner_valid_i = 1'b1;
        camera_w_stall_i = 1'b1;
        repeat (3) @(negedge clk_i);
        write_owner_geometry_i = 1'b1;
        camera_w_stall_i = 1'b0;
        repeat (2) @(negedge clk_i);
        wr_wvalid_i = 1'b0;
        write_owner_valid_i = 1'b0;
        hold_phase(3'd6, 2);
        geometry_done_i = 1'b1;
        @(negedge clk_i);
        geometry_done_i = 1'b0;
        geometry_phase_i = 3'd0;

        source_frame_i = 1'b1;
        display_flip_i = 1'b1;
        source_drop_count_i = 32'd1;
        reader_frame_count_i = 32'd1;
        underflow_count_i = 32'd2;
        cam0_frame_count_i = 32'd2;
        cam1_frame_count_i = 32'd3;
        pixel_frame_count_i = 32'd2;
        replaced_frame_count_i = 32'd1;
        input_stream_stall_i = 1'b1;
        output_stream_stall_i = 1'b1;
        mux_eof_i = 1'b1;
        unpack_frame_count_i = 32'd1;
        point_frame_count_i = 32'd1;
        spatial_frame_count_i = 32'd1;
        mux_valid_i = 1'b1;
        pixel_valid_i = 1'b1;
        active_camera_i = 1'b1;
        @(negedge clk_i);
        source_frame_i = 1'b0;
        display_flip_i = 1'b0;
        input_stream_stall_i = 1'b0;
        output_stream_stall_i = 1'b0;
        mux_eof_i = 1'b0;
        mux_valid_i = 1'b0;
        pixel_valid_i = 1'b0;

        wait (line_count_r == 1);
        expect_field(0, 32'd3);
        expect_field(1, 32'd2);
        expect_field(2, 32'd1);
        expect_field(3, 32'd1);
        expect_field(4, 32'd1);
        expect_field(5, 32'd0);
        expect_field(6, 32'd1);
        expect_field(7, 32'd1);
        expect_field(8, 32'd2);
        expect_field(14, 32'd1);
        expect_field(15, 32'd4);
        expect_field(23, 32'd0);
        expect_field(24, 32'd0);
        expect_field(25, 32'd2);
        expect_field(26, 32'd3);
        expect_field(27, 32'd2);
        expect_field(28, 32'd1);
        expect_field(29, 32'd1);
        expect_field(30, 32'd1);
        expect_field(19, 32'd5);
        expect_field(31, 32'd3);
        expect_field(32, 32'd3);
        expect_field(33, 32'd2);
        expect_field(34, 32'd1);
        expect_field(35, 32'd1);
        expect_field(36, 32'd1);
        expect_field(37, 32'd1);
        expect_field(38, 32'd0);
        expect_field(39, 32'd0);
        expect_field(40, 32'd0);
        expect_field(41, 32'd1);
        expect_field(42, 32'd1);
        expect_field(43, 32'd0);
        expect_field(44, 32'd0);
        expect_field(45, 32'd0);
        expect_field(46, 32'd1);
        if (field_r[9] < 32'd20 || field_r[10] == 32'b0 ||
            field_r[11] == 32'b0 || field_r[12] == 32'b0 ||
            field_r[13] == 32'b0 || field_r[17] == 32'b0 ||
            field_r[21] == 32'b0 || field_r[22] == 32'b0)
            $fatal(1, "missing phase or DDR metrics");
        checks_r = checks_r + 1;
        @(negedge clk_i);
        geometry_start_i = 1'b1;
        geometry_phase_i = 3'd2;
        @(negedge clk_i);
        geometry_start_i = 1'b0;
        wait (line_count_r == 2);
        expect_field(3, 32'd1);
        expect_field(4, 32'd0);
        expect_field(23, 32'd2);
        if (field_r[24] < 32'd1000)
            $fatal(1, "active frame elapsed counter missing");
        checks_r = checks_r + 1;
        $display("VISION_TELEMETRY_PASS checks=%0d total=%0d config=%0d prep=%0d fetch=%0d sample=%0d drain=%0d writer=%0d",
            checks_r, field_r[9], field_r[21], field_r[10],
            field_r[11], field_r[12], field_r[13], field_r[22]);
        $finish;
    end

    initial begin
        #3000000;
        $fatal(1, "telemetry timeout");
    end

endmodule
