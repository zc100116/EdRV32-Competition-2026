`timescale 1ns/1ps

module tb_render_board_telemetry;
    reg clk, rst_n;
    reg ddr_ready, command_done, base_done, base_w_fire;
    reg draw_start, draw_done, compose_start, compose_done;
    reg [15:0] draw_completed_count;
    reg [31:0] reader_frame_count, scanout_frame_count;
    reg [31:0] underflow_count;
    reg [31:0] render_read_beats, render_write_beats;
    reg [31:0] display_read_beats;
    reg [31:0] render_ar_wait, render_aw_wait, display_ar_wait;
    wire uart_tx;
    reg [7:0] sent_char [0:511];
    integer sent_count, cycles;

    always #5 clk = ~clk;

    edrv32_pango_200h_render_telemetry #(
        .CLK_HZ(160000),
        .UART_BAUD(16000),
        .REPORT_CYCLES(40000)
    ) u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .ddr_ready_i(ddr_ready),
        .command_done_i(command_done),
        .base_done_i(base_done),
        .base_w_fire_i(base_w_fire),
        .draw_start_i(draw_start), .draw_done_i(draw_done),
        .draw_completed_count_i(draw_completed_count),
        .compose_start_i(compose_start),
        .compose_done_i(compose_done),
        .reader_frame_count_i(reader_frame_count),
        .scanout_frame_count_i(scanout_frame_count),
        .underflow_count_i(underflow_count),
        .render_read_beats_i(render_read_beats),
        .render_write_beats_i(render_write_beats),
        .display_read_beats_i(display_read_beats),
        .render_ar_wait_i(render_ar_wait),
        .render_aw_wait_i(render_aw_wait),
        .display_ar_wait_i(display_ar_wait),
        .uart_tx_o(uart_tx)
    );

    task automatic tick_to;
        input integer target;
        begin
            while (cycles < target)
                @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ddr_ready = 1'b0;
        command_done = 1'b0;
        base_done = 1'b0;
        base_w_fire = 1'b0;
        draw_start = 1'b0;
        draw_done = 1'b0;
        compose_start = 1'b0;
        compose_done = 1'b0;
        draw_completed_count = 16'd0;
        reader_frame_count = 32'd0;
        scanout_frame_count = 32'd0;
        underflow_count = 32'd0;
        render_read_beats = 32'd0;
        render_write_beats = 32'd0;
        display_read_beats = 32'd0;
        render_ar_wait = 32'd0;
        render_aw_wait = 32'd0;
        display_ar_wait = 32'd0;
        sent_count = 0;
        cycles = 0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        ddr_ready = 1'b1;
        tick_to(10);
        command_done = 1'b1;
        base_w_fire = 1'b1;
        tick_to(14);
        command_done = 1'b0;
        base_w_fire = 1'b0;
        base_done = 1'b1;
        tick_to(15);
        base_done = 1'b0;
        tick_to(20);
        draw_start = 1'b1;
        tick_to(21);
        draw_start = 1'b0;
        tick_to(30);
        draw_completed_count = 16'd1;
        tick_to(40);
        draw_completed_count = 16'd2;
        draw_done = 1'b1;
        tick_to(41);
        draw_done = 1'b0;
        tick_to(42);
        compose_start = 1'b1;
        tick_to(43);
        compose_start = 1'b0;
        tick_to(50);
        compose_done = 1'b1;
        tick_to(51);
        compose_done = 1'b0;
        render_read_beats = 32'd10;
        render_write_beats = 32'd20;
        display_read_beats = 32'd30;
        render_ar_wait = 32'd2;
        render_aw_wait = 32'd3;
        display_ar_wait = 32'd4;
        scanout_frame_count = 32'd4;
        tick_to(60);
        reader_frame_count = 32'd1;
        wait(sent_count >= 14*21 + 7*21);
        #1;
        if (sent_char[0] != "R" || sent_char[1] != "P" ||
            sent_char[2] != "E" || sent_char[3] != "R" ||
            sent_char[4] != "F" || sent_char[6] != "C" ||
            sent_char[7] != "M" || sent_char[8] != "D" ||
            sent_char[9] != "C" || sent_char[19] != 8'h0d ||
            sent_char[20] != 8'h0a)
            $fatal(1,"RPERF prefix or framing mismatch");
        if (sent_char[7*21+6] != "R" ||
            sent_char[7*21+7] != "B" ||
            sent_char[7*21+8] != "T" ||
            sent_char[7*21+9] != "S" ||
            sent_char[7*21+17] != "0" ||
            sent_char[7*21+18] != "A")
            $fatal(1,"RPERF read-beat value mismatch");
        if (sent_char[14*21+0] != "R" ||
            sent_char[14*21+1] != "S" ||
            sent_char[14*21+2] != "T" ||
            sent_char[14*21+3] != "A" ||
            sent_char[14*21+4] != "T" ||
            sent_char[14*21+6] != "F" ||
            sent_char[14*21+7] != "P" ||
            sent_char[14*21+8] != "S" ||
            sent_char[14*21+9] != "0")
            $fatal(1,"RSTAT framing mismatch");
        if (sent_char[14*21+17] != "1" ||
            sent_char[14*21+18] != "0" ||
            sent_char[15*21+16] != "F" ||
            sent_char[15*21+17] != "0" ||
            sent_char[15*21+18] != "0")
            $fatal(1,"RSTAT FPS or HDMI byte rate mismatch");
        if (u_dut.perf_cmd_r == 32'd0 ||
            u_dut.perf_base_r == 32'd0 ||
            u_dut.perf_clear_r == 32'd0 ||
            u_dut.perf_round_r == 32'd0 ||
            u_dut.perf_compose_r == 32'd0 ||
            u_dut.perf_first_r <= u_dut.perf_compose_r)
            $fatal(1,"render phase timing snapshot mismatch");
        $display("RENDER_BOARD_TELEMETRY_PASS chars=%0d cycles=%0d",
                 sent_count,cycles);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (u_dut.send_active_r && u_dut.uart_ready_w) begin
                sent_char[sent_count] <= u_dut.uart_data_w;
                sent_count <= sent_count + 1;
            end
            if (cycles > 100000)
                $fatal(1,"render telemetry timeout sent=%0d",sent_count);
        end
    end
endmodule
